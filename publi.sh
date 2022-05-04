# Copyright 2022 Nokia
# Licensed under the BSD 3-Clause License.
# SPDX-License-Identifier: BSD-3-Clause

# publish container image to ghcr.io registry
# usage: bash publi.sh 21.11.1-105

#!/bin/bash
set -eu

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
sudo docker tag srlinux:$REL ghcr.io/nokia/srlinux:latest



# push
echo "pushing image to ghcr.io"
docker push ghcr.io/nokia/srlinux:$REL
docker push ghcr.io/nokia/srlinux:$SHORT_REL
docker push ghcr.io/nokia/srlinux:latest

# print
echo "Nokia SR Linux $SHORT_REL can be pulled using the following commands:"
echo "docker pull ghcr.io/nokia/srlinux:$SHORT_REL"
echo "docker pull ghcr.io/nokia/srlinux:$REL"
echo "docker pull ghcr.io/nokia/srlinux:latest"