#!/bin/bash
set -euo pipefail

# read in the image version variables
source version

# ARTIFACTORY_URL and ARTIFACTORY_TOKEN
if [[ ! -f .env ]]; then
    echo ".env is required (ARTIFACTORY_URL, ARTIFACTORY_TOKEN)" >&2
    exit 1
fi
# shellcheck disable=SC1091
source .env

OS="$(uname -s)"
BUILD_TYPE="${BUILD_TYPE:-release}"

# On Linux, egress interface MTU must be set to 1500.
# macOS / Docker Desktop does not need this workaround.
adjust_mtu() {
    local target_mtu="$1"

    if [[ "$OS" != "Linux" ]]; then
        return 0
    fi

    # Allow override; otherwise use the default route's interface.
    if [[ -z "${EGRESS_INTERFACE:-}" ]]; then
        EGRESS_INTERFACE=$(ip route show default | awk '{print $5; exit}')
    fi
    if [[ -z "$EGRESS_INTERFACE" ]]; then
        echo "Could not determine egress interface; set EGRESS_INTERFACE" >&2
        exit 1
    fi

    if [[ -z "${ORIGINAL_MTU:-}" ]]; then
        ORIGINAL_MTU=$(ip link show "$EGRESS_INTERFACE" | sed -n 's/.*mtu \([0-9]*\).*/\1/p')
        echo -n "Original MTU: $ORIGINAL_MTU. Setting $EGRESS_INTERFACE to ${target_mtu}... "
    else
        echo -n "Setting $EGRESS_INTERFACE back to original MTU ${target_mtu}... "
    fi

    sudo ip link set dev "$EGRESS_INTERFACE" mtu "$target_mtu"
    echo "Done"
}

# Docker Desktop on macOS does not need sudo; Linux typically does.
docker_cmd() {
    if [[ "$OS" == "Darwin" ]]; then
        docker "$@"
    else
        sudo -E docker "$@"
    fi
}

# engctl is a Linux ELF binary and cannot run on macOS.
can_use_engctl() {
    [[ "$OS" == "Linux" ]] || return 1
    command -v engctl >/dev/null 2>&1
}

download_with_engctl() {
    local arch="$1"
    engctl srlinux build download --files docker --version "$SRLREL" --number "$SRLBUILD" --arch "$arch"
}

download_with_curl() {
    local arch="$1"
    local archive="srldocker_${SRLREL}-${SRLBUILD}-${arch}.tar.xz"
    local remote="srldocker_${SRLREL}-${SRLBUILD}.tar.xz"
    local url="${ARTIFACTORY_URL}/srl-binary-local/srlinux-os/${SRLREL}/${BUILD_TYPE}/${SRLBUILD}/${arch}/${remote}"

    if [[ -z "${ARTIFACTORY_URL:-}" || -z "${ARTIFACTORY_TOKEN:-}" ]]; then
        echo "ARTIFACTORY_URL and ARTIFACTORY_TOKEN must be set in .env" >&2
        exit 1
    fi

    curl -fL --progress-bar \
        -H "X-JFrog-Art-Api: ${ARTIFACTORY_TOKEN}" \
        -o "$archive" \
        "$url"
}

download_image() {
    local arch="$1"

    echo -n "Pulling ${arch} image for ${SRLREL}-${SRLBUILD}... "
    if can_use_engctl; then
        download_with_engctl "$arch"
        # engctl writes a shared filename; rename so arches do not clobber each other
        if [[ -f "srldocker_${SRLREL}-${SRLBUILD}.tar.xz" ]]; then
            mv -f "srldocker_${SRLREL}-${SRLBUILD}.tar.xz" \
                "srldocker_${SRLREL}-${SRLBUILD}-${arch}.tar.xz"
        fi
    else
        echo "(via artifactory)"
        download_with_curl "$arch"
    fi
    echo "Done"
}

# Artifactory ships zstd payloads under a .tar.xz name; engctl may use real xz.
archive_cat() {
    local archive="$1"
    case "$(file -b "$archive")" in
        *Zstandard*|*zstd*) zstd -dc "$archive" ;;
        *XZ*|*xz*)          xz -dc "$archive" ;;
        *gzip*|*Gzip*)      gzip -dc "$archive" ;;
        *)                  cat "$archive" ;;
    esac
}

# OCI archives embed the image digest in index.json — more reliable than
# parsing `docker load` text (which reports "<name>:latest" for untagged images).
archive_image_digest() {
    local archive="$1"
    local arch="$2"

    archive_cat "$archive" | tar -xO index.json 2>/dev/null | python3 -c '
import json, sys
arch = sys.argv[1]
idx = json.load(sys.stdin)
manifests = idx.get("manifests") or []
for m in manifests:
    plat = m.get("platform") or {}
    if not arch or plat.get("architecture") == arch:
        print(m["digest"])
        raise SystemExit(0)
if manifests:
    print(manifests[0]["digest"])
' "$arch"
}

# Fallback when the archive is not OCI / has no index.json.
image_id_from_load() {
    local load_out="$1"
    local arch="$2"
    local ref repo id

    if echo "$load_out" | grep -q 'Loaded image ID:'; then
        echo "$load_out" | awk '/Loaded image ID:/ {print $NF; exit}'
        return 0
    fi

    ref=$(echo "$load_out" | awk '/Loaded image:/ {print $NF; exit}')
    [[ -n "$ref" ]] || return 1
    repo="${ref%%:*}"

    id=$(docker_cmd image inspect --format '{{.Id}}' "$ref" 2>/dev/null) && { echo "$id"; return 0; }
    id=$(docker_cmd image inspect --format '{{.Id}}' "$repo" 2>/dev/null) && { echo "$id"; return 0; }

    # Match repository name; prefer the requested architecture.
    while read -r candidate; do
        [[ -z "$candidate" ]] && continue
        if [[ -z "$arch" ]] || \
           [[ "$(docker_cmd image inspect --format '{{.Architecture}}' "$candidate")" == "$arch" ]]; then
            echo "$candidate"
            return 0
        fi
    done < <(docker_cmd images --no-trunc --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}' \
        | awk -v repo="$repo" -v ref="$ref" '
            $2 == repo || $2 ":" $3 == ref || $2 ":" $3 == repo { print $1 }
          ')

    return 1
}

load_and_tag() {
    local arch="$1"
    local archive="srldocker_${SRLREL}-${SRLBUILD}-${arch}.tar.xz"
    local full_tag="srlinux-${arch}:${SRLREL}-${SRLBUILD}"
    local short_tag="srlinux-${arch}:${SRLREL}"
    local load_out image_id digest ids_before

    download_image "$arch"

    if [[ ! -f "$archive" ]]; then
        echo "Missing archive: $archive" >&2
        exit 1
    fi

    digest=$(archive_image_digest "$archive" "$arch" || true)
    ids_before=$(docker_cmd images -q --no-trunc | sort -u)

    echo -n "Loading ${arch} docker image ${archive}... "
    load_out=$(docker_cmd load -i "$archive")
    echo "$load_out"

    if [[ -n "$digest" ]] && docker_cmd image inspect "$digest" >/dev/null 2>&1; then
        image_id="$digest"
    else
        image_id=$(comm -13 <(echo "$ids_before") <(docker_cmd images -q --no-trunc | sort -u) | head -1 || true)
    fi
    if [[ -z "$image_id" ]]; then
        image_id=$(image_id_from_load "$load_out" "$arch" || true)
    fi
    if [[ -z "$image_id" ]]; then
        echo "Failed to resolve loaded image ID" >&2
        exit 1
    fi
    echo "Using image id: $image_id"

    echo -n "Tagging ${arch} image as ${full_tag} and ${short_tag}... "
    docker_cmd tag "$image_id" "$full_tag"
    docker_cmd tag "$image_id" "$short_tag"
    if [[ "${SRL_LATEST}" != "no" ]]; then
        docker_cmd tag "$image_id" "srlinux-${arch}:latest"
        echo -n "and srlinux-${arch}:latest... "
    fi
    echo "Done"

    echo -n "Removing ${arch} docker image ${archive}... "
    rm -f "$archive"
    echo "Done"
}

ORIGINAL_MTU=""
adjust_mtu 1500

load_and_tag amd64
load_and_tag arm64

if [[ -n "${ORIGINAL_MTU}" ]]; then
    adjust_mtu "$ORIGINAL_MTU"
fi
