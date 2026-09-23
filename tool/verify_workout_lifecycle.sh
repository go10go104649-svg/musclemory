#!/bin/bash
# Usage: FLUTTER_BIN=/path/to/flutter ./tool/verify_workout_lifecycle.sh ios DEVICE_ID
# Android also needs the project's existing JAVA_HOME and ANDROID_HOME setup.
set -euo pipefail
cd "$(dirname "$0")/.."
qa_platform=${1:?Specify ios or android}
qa_device=${2:?Specify a simulator/emulator device ID}
qa_flutter=${FLUTTER_BIN:-flutter}
qa_target=${MUSCLEMORY_QA_TARGET:-integration_test/workout_lifecycle_test.dart}
qa_driver=test_driver/workout_lifecycle_driver.dart
qa_candidates=${FORM_QA_REVIEW_CANDIDATES-}
if [[ -n "$qa_candidates" ]]; then
  [[ "$qa_target" == integration_test/exercise_form_route_test.dart && "$qa_candidates" == "${FORM_QA_IDS-}" ]] || {
    echo 'Review candidates require the route target and matching explicit FORM_QA_IDS.' >&2; exit 2;
  }
fi
case "$qa_platform" in
  ios)
    qa_name=$(xcrun simctl list devices -j | python3 -c 'import json,sys; print(next((d["name"] for group in json.load(sys.stdin)["devices"].values() for d in group if d["udid"] == sys.argv[1]), ""))' "$qa_device")
    [[ "$qa_name" == MUSCLEMORY\ QA* ]] || { echo 'Use a dedicated MUSCLEMORY QA simulator, never a user simulator.' >&2; exit 2; }
    ;;
  android)
    qa_name=$("${ANDROID_HOME:?Set ANDROID_HOME}/platform-tools/adb" -s "$qa_device" emu avd name | head -1 | tr -d '\r')
    [[ "$qa_name" == musclemory_qa || "$qa_name" == MUSCLEMORY_Batch_QA ]] || { echo 'Use the dedicated musclemory_qa or MUSCLEMORY_Batch_QA emulator.' >&2; exit 2; }
    ;;
  *) echo 'Platform must be ios or android' >&2; exit 2 ;;
esac
qa_defines=()
qa_mode=${FORM_QA_MODE-full}
case "$qa_mode" in
  full|light) ;;
  *) echo 'FORM_QA_MODE must be full or light.' >&2; exit 2 ;;
esac
if [[ "$qa_mode" == light ]]; then
  [[ "$qa_target" == integration_test/exercise_form_expansion_test.dart && -n "${FORM_QA_IDS-}" && -n "${FORM_QA_BASELINE-}" ]] || {
    echo 'Light mode requires the form expansion target, explicit IDs and baseline evidence.' >&2; exit 2;
  }
fi
if [[ "$qa_target" == integration_test/exercise_form_expansion_test.dart || "$qa_target" == integration_test/exercise_form_route_test.dart ]]; then
  qa_defines=("--dart-define=FORM_QA_MODE=$qa_mode" "--dart-define=FORM_QA_IDS=${FORM_QA_IDS-}" "--dart-define=FORM_QA_BASELINE=${FORM_QA_BASELINE-}")
fi
qa_test_scope=${FORM_QA_TEST_SCOPE-all}
case "$qa_test_scope" in
  all) qa_tests=() ;;
  forms)
    [[ "$qa_target" == integration_test/exercise_form_expansion_test.dart || "$qa_target" == integration_test/exercise_form_route_test.dart ]] || {
      echo 'Forms-only tests require a form QA target.' >&2; exit 2;
    }
    qa_tests=(test/exercise_form_catalog_test.dart test/bench_press_form_test.dart test/form_qa_plan_test.dart)
    ;;
  *) echo 'FORM_QA_TEST_SCOPE must be all or forms.' >&2; exit 2 ;;
esac
"$qa_flutter" analyze
"$qa_flutter" test ${qa_tests[@]+"${qa_tests[@]}"}
if [[ -n "$qa_candidates" ]]; then
  # Unit tests inspect the normal catalog. Only the route build gets the
  # temporary candidate catalog, after the generator validates all prior gates.
  restore_catalog() {
    qa_result=$?
    trap - EXIT
    python3 tool/exercise_forms/generate_catalog.py || exit 1
    exit "$qa_result"
  }
  trap restore_catalog EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  python3 tool/exercise_forms/generate_catalog.py --review-candidates "$qa_candidates"
fi
case "$qa_platform" in
  ios)
    "$qa_flutter" build ios --simulator --debug --target="$qa_target" ${qa_defines[@]+"${qa_defines[@]}"}
    qa_binary=build/ios/iphonesimulator/Runner.app
    ;;
  android)
    "$qa_flutter" build apk --debug --target-platform=android-arm64 --target="$qa_target" ${qa_defines[@]+"${qa_defines[@]}"}
    qa_binary=build/app/outputs/flutter-apk/app-debug.apk
    ;;
  *) echo 'Platform must be ios or android' >&2; exit 2 ;;
esac
# Never let a failed build fall through to an old installed app.
"$qa_flutter" drive --keep-app-running --no-dds --use-application-binary="$qa_binary" \
  --driver="$qa_driver" -d "$qa_device"
