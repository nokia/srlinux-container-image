# Copyright 2022 Nokia
# Licensed under the BSD 3-Clause License.
# SPDX-License-Identifier: BSD-3-Clause

# publish container image to ghcr.io registry and tag with full tag, short tag, major version tag and latest tag
# usage: `bash publi.sh 21.11.1-105`
# if latest tag shouldn't be added, use: `SRL_LATEST=no bash publi.sh 21.11.1-105`
# if major version tag shouldn't be added, use: `SRL_MAJOR=no bash publi.sh 21.11.1-105`
# to just create container images out of the tar.xz archive without pushing them to the registry:
# use `NO_PUSH=true bash publi.sh 21.11.1-105`
# the expectation is that srlinux-arm64:<long-version> and amd64 image is already available locally
# this is done by the `pull.sh` script.


#!/bin/bash
set -e

# REL is the original release version/tag, i.e. 21.11.1-105
REL=$1

# short version is one without the build tag - 21.11.1
SHORT_REL=$(echo ${REL} | cut -d "-" -f 1)
# major version is one without the minor fix version - 21.11
MAJOR_REL=$(echo ${REL} | cut -d "." -f 1,2)

ORIG_SRL_AMD64_IMAGE="srlinux-amd64:${REL}"
ORIG_SRL_ARM64_IMAGE="srlinux-arm64:${REL}"

# verify that image's CMD and ENTRYPOINT haven't changed
CMD=$(docker inspect $ORIG_SRL_AMD64_IMAGE -f '{{.Config.Cmd}}')
ENTRYPOINT=$(docker inspect $ORIG_SRL_AMD64_IMAGE -f '{{.Config.Entrypoint}}')

if [[ $ENTRYPOINT != "[/tini -- /usr/local/bin/fixuid -q /entrypoint.sh]" ]]; then
    echo "entrypoint changed: $ENTRYPOINT"
    exit 1
fi

if [[ $CMD != "[/bin/bash]" ]]; then
    echo "cmd changed: $CMD"
    exit 1
fi

# tag
echo "tagging image"

GHCR_PREFIX="ghcr.io/nokia/srlinux"
AMD_IMAGE=$ORIG_SRL_AMD64_IMAGE
AMD_GHCR_IMAGE="${GHCR_PREFIX}:${REL}-amd64"
ARM_IMAGE=$ORIG_SRL_ARM64_IMAGE
ARM_GHCR_IMAGE="${GHCR_PREFIX}:${REL}-arm64"

# tagging the original per-platform image to the ghcr per platform
sudo -E docker tag $AMD_IMAGE $AMD_GHCR_IMAGE # amd
sudo -E docker tag $ARM_IMAGE $ARM_GHCR_IMAGE # arm

# skipping pushing images if NO_PUSH env var is set
if [[ "${NO_PUSH}" != "" ]]; then
    echo "skipping push of the images and manifests"
    exit 0
fi

# push
echo "pushing images to ghcr.io"
# pushing individual images
docker push ${ARM_GHCR_IMAGE}
docker push ${AMD_GHCR_IMAGE}

# cleanup old manifests if they exist
sudo -E docker manifest rm ${GHCR_PREFIX}:${REL} || true
sudo -E docker manifest rm ${GHCR_PREFIX}:${SHORT_REL} || true
sudo -E docker manifest rm ${GHCR_PREFIX}:${MAJOR_REL} || true
sudo -E docker manifest rm ${GHCR_PREFIX}:latest || true

# creating versioned manifest
# full version
sudo -E docker manifest create ${GHCR_PREFIX}:${REL} \
    ${AMD_GHCR_IMAGE} \
    ${ARM_GHCR_IMAGE}
sudo -E docker manifest push ${GHCR_PREFIX}:${REL}

# short version
sudo -E docker manifest create ${GHCR_PREFIX}:${SHORT_REL} \
    ${AMD_GHCR_IMAGE} \
    ${ARM_GHCR_IMAGE}
sudo -E docker manifest push ${GHCR_PREFIX}:${SHORT_REL}


# creating the latest manifest only if env var SRL_LATEST is not set to `no`
# this is to skip tagging non most recent releases as latest
# e.g. when 24.10.5 is released, but most recent version is 25.3 already
if [[ "${SRL_LATEST}" != "no" ]]; then
    sudo -E docker manifest create ${GHCR_PREFIX}:latest \
        ${AMD_GHCR_IMAGE} \
        ${ARM_GHCR_IMAGE}
    sudo -E docker manifest push ${GHCR_PREFIX}:latest
fi

# create the major version manifest only if env var SRL_MAJOR is not set to `no`
# this skips tagging the major version if say, we push an older minor version
# that is not necessarily the latest minor version.
# e.g. 24.10.2 pushed again while 24.10.4 is already released
if [[ "${SRL_MAJOR}" != "no" ]]; then
    sudo -E docker manifest create ${GHCR_PREFIX}:${MAJOR_REL} \
        ${AMD_GHCR_IMAGE} \
        ${ARM_GHCR_IMAGE}
    sudo -E docker manifest push ${GHCR_PREFIX}:${MAJOR_REL}
fi

# print
echo "Nokia SR Linux $SHORT_REL can be pulled using the following commands:"
echo "docker pull ghcr.io/nokia/srlinux:$REL"
echo "docker pull ghcr.io/nokia/srlinux:$SHORT_REL"
if [[ "${SRL_MAJOR}" != "no" ]]; then
    echo "docker pull ghcr.io/nokia/srlinux:$MAJOR_REL"
fi
if [[ "${SRL_LATEST}" != "no" ]]; then
    echo "docker pull ghcr.io/nokia/srlinux:latest"
fi

# remove local manifests so they don't mess up with subsequent runs of this script
sudo -E docker manifest rm ${GHCR_PREFIX}:${REL}
sudo -E docker manifest rm ${GHCR_PREFIX}:${SHORT_REL}
sudo -E docker manifest rm ${GHCR_PREFIX}:${MAJOR_REL}
sudo -E docker manifest rm ${GHCR_PREFIX}:latest
