#!/usr/bin/env bash
# 감사일기 macOS 앱을 Developer ID로 서명 → dmg 생성 → 공증(notarize) → 스테이플
#
# 사전 준비 (최초 1회)
#   1) Xcode > Settings > Accounts 에 Apple Developer 계정 로그인 (유료 멤버십 필요)
#   2) Scripts/ExportOptions.plist 의 YOUR_TEAM_ID 교체
#   3) 공증용 키체인 프로필 저장:
#        xcrun notarytool store-credentials "gratitude-notary" \
#          --apple-id "you@example.com" --team-id "YOUR_TEAM_ID" --password "<앱 암호>"
#
# 사용법
#   ./Scripts/build_dmg.sh                 # 전체 (서명 + 공증)
#   SKIP_NOTARIZE=1 ./Scripts/build_dmg.sh # 내 Mac 테스트용 (공증 생략)
set -euo pipefail

PROJECT="GratitudeJournal.xcodeproj"
SCHEME="GratitudeJournal"
APP_NAME="GratitudeJournal"
VOLUME_NAME="감사일기"
NOTARY_PROFILE="${NOTARY_PROFILE:-gratitude-notary}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
ARCHIVE="$BUILD/$APP_NAME.xcarchive"
EXPORT="$BUILD/export"
cd "$ROOT"

rm -rf "$BUILD"; mkdir -p "$BUILD"

echo "▶︎ 1/5 아카이브 (Release, macOS)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" \
  archive

echo "▶︎ 2/5 Developer ID 서명으로 내보내기"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$ROOT/Scripts/ExportOptions.plist"

APP="$EXPORT/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$BUILD/$APP_NAME-$VERSION.dmg"

echo "▶︎ 3/5 dmg 생성 (앱 + /Applications 바로가기)"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "⚠︎ 공증 생략: $DMG (다른 Mac에서는 Gatekeeper 경고가 뜹니다)"
  exit 0
fi

echo "▶︎ 4/5 공증 제출 (수 분 소요)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▶︎ 5/5 스테이플 & 검증"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

echo "✅ 완료: $DMG"
