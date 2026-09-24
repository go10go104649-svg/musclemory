#!/bin/bash
# Local beta build only. Never uploads or installs on a user device.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${MUSCLEMORY_SIGNING_PROPERTIES:?Set the path to private signing.properties}"
[[ -r "$MUSCLEMORY_SIGNING_PROPERTIES" ]] || { echo 'Private signing file not readable.' >&2; exit 2; }
qa_flutter=${FLUTTER_BIN:-flutter}
qa_config=${MUSCLEMORY_SUPABASE_CONFIG:-supabase.json}
[[ -r "$qa_config" ]] || { echo 'Supabase build configuration is required.' >&2; exit 2; }
python3 - "$qa_config" <<'CHECK_CONFIG'
import json, sys
try:
    with open(sys.argv[1]) as source:
        config = json.load(source)
    if not config.get('SUPABASE_URL') or not (
        config.get('SUPABASE_PUBLISHABLE_KEY') or config.get('SUPABASE_ANON_KEY')
    ):
        raise ValueError()
except (OSError, ValueError, TypeError, AttributeError):
    sys.exit('Supabase URL and public key must be present in the build configuration.')
CHECK_CONFIG
"$qa_flutter" analyze
"$qa_flutter" test
"$qa_flutter" build apk --release --dart-define-from-file="$qa_config"
# Google Play requires a bundle, but it is not directly installable on a phone.
if [[ "${BUILD_PLAY_BUNDLE:-0}" == 1 ]]; then
  "$qa_flutter" build appbundle --release --dart-define-from-file="$qa_config"
fi
