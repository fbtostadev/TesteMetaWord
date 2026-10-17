#!/bin/zsh
# Runs the tests and prints only failures and the summary (`-quiet` would hide Swift Testing failures).
#   ./scripts/test.sh        logic tests only, the everyday loop (seconds)
#   ./scripts/test.sh ui     the single interface flow (drag, fusion, Undo, long press)
#   ./scripts/test.sh all    both, before integrating into main
# DESTINATION overrides the simulator, e.g. DESTINATION='platform=iOS Simulator,id=<UDID>'.
set -euo pipefail

cd "${0:A:h:h}"
case "${1:-logic}" in
  logic) only=(-only-testing:TesteMetaWordTests) ;;
  ui) only=(-only-testing:TesteMetaWordUITests) ;;
  all) only=() ;;
  *) print -u2 "uso: $0 [logic|ui|all]"; exit 64 ;;
esac
xcodebuild test \
  -project TesteMetaWord.xcodeproj \
  -scheme TesteMetaWord \
  -destination "${DESTINATION:-platform=iOS Simulator,name=iPad Pro 13-inch (M5)}" \
  -derivedDataPath build/DerivedData \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  "${only[@]}" 2>&1 | grep -E '✘|error:|Test Case .* failed|Test run with|Executed [0-9]+ test|\*\* TEST' | grep -v ' 0 tests'
exit ${pipestatus[1]}
