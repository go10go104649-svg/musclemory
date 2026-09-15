#!/bin/bash
# Local beta build only. Never uploads or installs on a user device.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${MUSCLEMORY_SIGNING_PROPERTIES:?Set the path to private signing.properties}"
[[ -r "$MUSCLEMORY_SIGNING_PROPERTIES" ]] || { echo 'Private signing file not readable.' >&2; exit 2; }
qa_flutter=${FLUTTER_BIN:-flutter}
"$qa_flutter" analyze
"$qa_flutter" test
"$qa_flutter" build apk --release
# Google Play requires a bundle, but it is not directly installable on a phone.
if [[ "${BUILD_PLAY_BUNDLE:-0}" == 1 ]]; then
  "$qa_flutter" build appbundle --release
fi
