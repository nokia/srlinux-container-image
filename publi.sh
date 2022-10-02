# Copyright 2022 Nokia
# Licensed under the BSD 3-Clause License.
# SPDX-License-Identifier: BSD-3-Clause

# publish container image to ghcr.io registry and tag with full tag, short tag and latest tag
# usage: `bash publi.sh 21.11.1-105`
# if latest tag shouldn't be added, use: `SRL_LATEST=no bash publi.sh 21.11.1-105`
# to just create container images out of the tar.xz archive without pushing them to the registry:
# use `NO_PUSH=true bash publi.sh 21.11.1-105`

#!/bin/bash
set -e

# REL is the original release version/tag, i.e. 21.11.1-105
REL=$1

# short version is one without the build tag - 21.11.1
SHORT_REL=$(echo ${REL} | cut -d "-" -f 1)

# verify that image's CMD and ENTRYPOINT haven't changed
CMD=$(docker inspect srlinux:$REL -f '{{.Config.Cmd}}')
ENTRYPOINT=$(docker inspect srlinux:$REL -f '{{.Config.Entrypoint}}')

if [[ $ENTRYPOINT != "[/tini -- fixuid -q /entrypoint.sh]" ]]; then
    echo "entrypoint changed: $ENTRYPOINT"
    exit 1
fi

if [[ $CMD != "[/bin/bash]" ]]; then
    echo "cmd changed: $CMD"
    exit 1
fi

# tag
echo "tagging image"
sudo docker tag srlinux:$REL ghcr.io/nokia/srlinux:$REL
sudo docker tag srlinux:$REL ghcr.io/nokia/srlinux:$SHORT_REL
# skipping tagging latest if env var SRL_LATEST is set to any value
# this is to skip tagging non most recent release as latest
if [[ "${SRL_LATEST}" != "no" ]]; then
    sudo docker tag srlinux:$REL ghcr.io/nokia/srlinux:latest
fi

# skipping pushing images if NO_PUSH env var is set
if [[ "${NO_PUSH}" != "" ]]; then
    echo "skipping push of the images"
    exit 0
fi

# push
echo "pushing image to ghcr.io"
docker push ghcr.io/nokia/srlinux:$REL
docker push ghcr.io/nokia/srlinux:$SHORT_REL
if [[ "${SRL_LATEST}" != "no" ]]; then
    docker push ghcr.io/nokia/srlinux:latest
fi

# print
echo "Nokia SR Linux $SHORT_REL can be pulled using the following commands:"
echo "docker pull ghcr.io/nokia/srlinux:$SHORT_REL"
echo "docker pull ghcr.io/nokia/srlinux:$REL"
if [[ "${SRL_LATEST}" != "no" ]]; then
    echo "docker pull ghcr.io/nokia/srlinux:latest"
fi
