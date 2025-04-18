# Copyright 2022 Nokia
# Licensed under the BSD 3-Clause License.
# SPDX-License-Identifier: BSD-3-Clause

# add gh release, this triggers email notifications to the subscribers
# use `bash add-release.sh 23.10.5`

#!/bin/bash
set -e

# REL is the short release version/tag, i.e. 23.10.5
REL=$1

# cleanup previous notes
rm -f notes.md

# if release is empty exit
if [[ -z "$REL" ]]; then
    echo "release version is empty"
    exit 1
fi

# template the release notes
sed "s/{{version}}/$REL/g" notes.md.j2 > notes.md

# add release
gh release create ${REL} --notes-file notes.md