#!/bin/bash

ARCHIVE_URL=$1
ARCHIVE_FILE_BASEPATH=$(basename ${ARCHIVE_URL})
ARCHIVE_SUFFIX=".tar.gz"

rm -f $ARCHIVE_FILE_BASEPATH

wget $ARCHIVE_URL -q
CHECKSUM=$(cat $ARCHIVE_FILE_BASEPATH | openssl dgst -sha256 -binary | openssl base64 -A)

MODULE_NAME=$(echo "$ARCHIVE_FILE_BASEPATH" | sed -E 's/-[0-9\.]+\.tar\.gz$//g')
VERSION=$(echo "$ARCHIVE_FILE_BASEPATH" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]')

mkdir -p "modules/$MODULE_NAME/$VERSION"

tar -Oxzf $ARCHIVE_FILE_BASEPATH "${ARCHIVE_FILE_BASEPATH%$ARCHIVE_SUFFIX}/MODULE.bazel" > "modules/$MODULE_NAME/$VERSION/MODULE.bazel"

rm -f $ARCHIVE_FILE_BASEPATH

echo "{
  \"url\": \"${ARCHIVE_URL}\",
  \"integrity\": \"sha256-${CHECKSUM}\",
  \"strip_prefix\": \"${ARCHIVE_FILE_BASEPATH%$ARCHIVE_SUFFIX}\"
}" > "modules/$MODULE_NAME/$VERSION/source.json"


echo "matrix:
  platform:
    - debian11
    - ubuntu2204
    - macos
    - macos_arm64
    - windows
  bazel:
    - 8.x
tasks:
  verify_targets:
    name: Verify build targets
    platform: \${{ platform }}
    bazel: \${{ bazel }}
    build_targets:
      - \"@$MODULE_NAME//...\"
    test_targets:
      - \"@$MODULE_NAME//...\"
" > "modules/$MODULE_NAME/$VERSION/presubmit.yml"