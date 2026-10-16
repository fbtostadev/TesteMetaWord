#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
xcodebuild \
  -project TesteMetaWord.xcodeproj \
  -scheme TesteMetaWord \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  "$@" \
  build
