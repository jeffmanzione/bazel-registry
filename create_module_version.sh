#!/bin/bash
# Adds a module version to the registry from its release archive.
#
# Usage: ./create_module_version.sh <archive URL>
#
# The archive must be named <module>-<version>.tar.gz and contain everything
# under <module>-<version>/, as the modules' release workflows publish it.
set -euo pipefail

ARCHIVE_URL=$1
ARCHIVE_FILE=$(basename "$ARCHIVE_URL")
ARCHIVE_SUFFIX=".tar.gz"
PREFIX=${ARCHIVE_FILE%$ARCHIVE_SUFFIX}

MODULE_NAME=$(echo "$PREFIX" | sed -E 's/-[0-9]+\.[0-9]+\.[0-9]+$//')
VERSION=${PREFIX#$MODULE_NAME-}
if [ "$MODULE_NAME" = "$PREFIX" ]; then
  echo "Expected an archive named <module>-<version>$ARCHIVE_SUFFIX, got $ARCHIVE_FILE." >&2
  exit 1
fi

MODULE_DIR="modules/$MODULE_NAME"
VERSION_DIR="$MODULE_DIR/$VERSION"
if [ ! -f "$MODULE_DIR/metadata.json" ]; then
  echo "$MODULE_DIR/metadata.json does not exist. Add it for a new module." >&2
  exit 1
fi
if [ -e "$VERSION_DIR" ]; then
  echo "$VERSION_DIR already exists." >&2
  exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fsSL -o "$TMP_DIR/$ARCHIVE_FILE" "$ARCHIVE_URL"
CHECKSUM=$(openssl dgst -sha256 -binary "$TMP_DIR/$ARCHIVE_FILE" | openssl base64 -A)

mkdir -p "$VERSION_DIR"
tar -Oxzf "$TMP_DIR/$ARCHIVE_FILE" "$PREFIX/MODULE.bazel" > "$VERSION_DIR/MODULE.bazel"
if ! grep -qE "^ *version = \"$VERSION\"," "$VERSION_DIR/MODULE.bazel"; then
  echo "The archive's MODULE.bazel does not declare version $VERSION." >&2
  rm -rf "$VERSION_DIR"
  exit 1
fi

echo "{
  \"url\": \"${ARCHIVE_URL}\",
  \"integrity\": \"sha256-${CHECKSUM}\",
  \"strip_prefix\": \"${PREFIX}\"
}" > "$VERSION_DIR/source.json"

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
" > "$VERSION_DIR/presubmit.yml"

# Adds the version to metadata.json, keeping versions sorted and the file's
# formatting.
python3 - "$MODULE_DIR/metadata.json" "$VERSION" <<'PY'
import json, re, sys
path, version = sys.argv[1], sys.argv[2]
text = open(path).read()
versions = json.loads(text)["versions"]
if version not in versions:
    versions.append(version)
versions.sort(key=lambda v: [int(p) for p in v.split(".")])
listed = ", ".join(json.dumps(v) for v in versions)
text, count = re.subn(r'"versions": \[[^\]]*\]', '"versions": [' + listed + ']', text)
assert count == 1, "Expected one versions list in " + path
open(path, "w").write(text)
PY

echo "Added $MODULE_NAME $VERSION."
