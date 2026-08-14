#!/bin/bash

export EGRESS_INTERFACE="eno1"

# read in the image version variables
source version

# make sure to set the mtu of the mgmt interface to 1500, otherwise
# artifactory is not happy

ORIGINAL_MTU=$(sudo ip link show eno1 | grep -Po 'mtu \K[0-9]+')
echo -n "Original MTU: $ORIGINAL_MTU. Setting $EGRESS_INTERFACE to 1500... "
sudo ip l set dev $EGRESS_INTERFACE mtu 1500
echo "Done"

# pull amd64 image
echo -n "Pulling amd64 image for $SRLREL-$SRLBUILD... "
engctl srlinux build download --files docker --version $SRLREL --number $SRLBUILD --arch amd64
echo "Done"
echo -n "Loading amd64 docker image srldocker_$SRLREL-$SRLBUILD.tar.xz... "
sudo -E IMAGE_TAG=$(docker load -i srldocker_$SRLREL-$SRLBUILD.tar.xz | awk '/Loaded image/ {print $NF}')
echo "Done - image tag: $IMAGE_TAG"
echo -n "Tagging amd64 image as srlinux-amd64:$SRLREL-$SRLBUILD... "
sudo -E docker tag $IMAGE_TAG srlinux-amd64:$SRLREL-$SRLBUILD
echo "Done"
echo -n "Removing amd64 docker image srldocker_$SRLREL-$SRLBUILD.tar.xz... "
# rm -f srldocker_$SRLREL-$SRLBUILD.tar.xz
echo "Done"

# pull arm64 image
echo -n "Pulling arm64 image for $SRLREL-$SRLBUILD... "
engctl srlinux build download --files docker --version $SRLREL --number $SRLBUILD --arch arm64
echo "Done"
echo -n "Loading arm64 docker image srldocker_$SRLREL-$SRLBUILD.tar.xz... "
sudo -E IMAGE_TAG=$(docker load -i srldocker_$SRLREL-$SRLBUILD.tar.xz | awk '/Loaded image/ {print $NF}')
echo "Done - image tag: $IMAGE_TAG"
echo -n "Tagging arm64 image as srlinux-arm64:$SRLREL-$SRLBUILD... "
sudo -E docker tag $IMAGE_TAG srlinux-arm64:$SRLREL-$SRLBUILD
echo "Done"
echo -n "Removing arm64 docker image srldocker_$SRLREL-$SRLBUILD.tar.xz... "
rm -f srldocker_$SRLREL-$SRLBUILD.tar.xz
echo "Done"

echo -n "Setting $EGRESS_INTERFACE back to original MTU $ORIGINAL_MTU... "
sudo ip l set dev $EGRESS_INTERFACE mtu $ORIGINAL_MTU
echo "Done"
