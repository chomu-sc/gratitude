# 감사일기 (GratitudeJournal) — SwiftUI Universal App

iOS · macOS 하나의 코드베이스. SwiftData + CloudKit(iCloud)로 자동 동기화, macOS 메뉴 막대 상주 + `⌘⇧G` 전역 빠른 작성.

- 최소 버전: **iOS 17 / macOS 14 (Sonoma)**, Xcode 16 이상
- 외부 의존성: 없음

---

## 1. 아키텍처 선택: 옵션 B (Apple Native)

| 요구사항 | 옵션 A (React Native + Electron + Firebase) | 옵션 B (SwiftUI + SwiftData + CloudKit) |
|---|---|---|
| iOS ↔ macOS 동기화 | Firebase 프로젝트·인증(로그인 화면)·보안 규칙 직접 구축 | 기기의 Apple ID로 **로그인 없이** 자동. 서버 0개 |
| 감정 기록 같은 사적 데이터 | 개발자 Firebase에 저장 | 사용자 **개인 iCloud DB**에 저장, 개발자도 열람 불가 |
| 메뉴 막대 상주 | Electron `Tray` (Chromium 상주 → 메모리 150MB+) | `MenuBarExtra` (수십 MB) |
| 전역 단축키 | `globalShortcut` | Carbon `RegisterEventHotKey` (권한 불필요) |
| 애플 일기 스타일 UI·햅틱 | 흉내 내야 함 | 시스템 컴포넌트·`sensoryFeedback` 그대로 |
| 코드베이스 | RN + Electron(웹) **두 개**의 UI | **한 개** (`#if os(macOS)`로 분기) |
| dmg | electron-builder | `xcodebuild` + `hdiutil` + notarytool |

대상이 Apple 플랫폼뿐이라면 A의 장점(Android/Windows/Web 확장성)이 쓸모가 없고, 비용(서버·인증·두 개의 UI·메모리)만 남습니다.
**나중에 Android/Windows가 꼭 필요해지면** 그때 A를 고려하세요 — CloudKit 데이터는 CloudKit JS/Web Services로 꺼낼 수는 있지만 이전 작업이 필요합니다.

---

## 2. 디렉토리 구조

```
GratitudeJournal/
├─ GratitudeJournal/
│  ├─ App/
│  │  ├─ GratitudeJournalApp.swift     # Scene: WindowGroup + MenuBarExtra + Settings
│  │  └─ AppDelegate.swift             # (macOS) 전역 단축키 등록, 창 닫아도 상주
│  ├─ Models/
│  │  ├─ GratitudeEntry.swift          # @Model 스키마 (CloudKit 호환)
│  │  ├─ EmotionLevel.swift            # 1~7 감정 enum (라벨·색상·얼굴 곡률)
│  │  └─ EntryDraft.swift              # 편집용 값 타입 (저장 시점에만 커밋)
│  ├─ Services/
│  │  ├─ AppContainer.swift            # 공유 ModelContainer (CloudKit private DB)
│  │  ├─ EntryRepository.swift         # CRUD
│  │  └─ SyncMonitor.swift             # iCloud 동기화 상태 관찰
│  ├─ Views/
│  │  ├─ ContentView.swift             # 날짜별 목록 + 상세 (NavigationSplitView)
│  │  ├─ EntryEditorView.swift         # 메인 에디터
│  │  └─ Components/
│  │     ├─ EmotionSlider.swift        # ★ 7단계 감정 슬라이더
│  │     ├─ MoodFace.swift             # 감정별로 모핑되는 스마일 얼굴
│  │     └─ SyncStatusView.swift
│  ├─ macOS/                           # ← 타깃 멤버십: macOS 전용 (파일 내부도 #if os(macOS))
│  │  ├─ GlobalHotKey.swift            # ★ ⌘⇧G 전역 단축키 (Carbon)
│  │  ├─ QuickEntryPanel.swift         # ★ 플로팅 패널 + 컨트롤러
│  │  ├─ QuickEntryView.swift          # 빠른 작성 폼 (패널·메뉴 막대 공용)
│  │  ├─ MenuBarContentView.swift      # 메뉴 막대 팝오버
│  │  └─ SettingsView.swift            # 로그인 시 실행, Dock 숨김
│  ├─ Resources/Assets.xcassets/AppIcon.appiconset/   # 노란 스마일 아이콘 (생성됨)
│  └─ Supporting/*.entitlements
└─ Scripts/
   ├─ generate_icon.py                 # 아이콘 재생성
   ├─ build_dmg.sh                     # 아카이브 → dmg → 공증
   └─ ExportOptions.plist
```

---

## 3. Xcode 프로젝트 세팅 (처음 한 번)

1. **File ▸ New ▸ Project ▸ Multiplatform ▸ App**
   - Product Name `GratitudeJournal`, Interface SwiftUI, Storage **None** (직접 구성하므로)
   - Bundle ID 예: `com.yourname.GratitudeJournal`
2. Xcode가 만든 `ContentView.swift`, `GratitudeJournalApp.swift`, `Assets.xcassets`를 지우고 이 저장소의 `GratitudeJournal/` 폴더 전체를 드래그해서 추가 (Copy items if needed, 타깃 체크).
3. **타깃 ▸ Signing & Capabilities** (iOS·macOS 둘 다)
   - `+ Capability` → **iCloud** → *CloudKit* 체크 → 컨테이너 `iCloud.com.yourname.GratitudeJournal` 생성
   - `+ Capability` → **Push Notifications**
   - (iOS) `+ Capability` → **Background Modes** → *Remote notifications* 체크
   - (macOS) App Sandbox → *Outgoing Connections (Client)* 체크
4. 컨테이너 ID를 코드에 맞추기: `Services/AppContainer.swift`의 `cloudKitContainerID`, `Supporting/*.entitlements` 3개 파일의 문자열.
5. Xcode가 엔타이틀먼트 파일을 자동 생성했다면 그것을 써도 되고, 동봉한 파일을 쓰려면 Build Settings ▸ **Code Signing Entitlements**를 플랫폼·구성별로 지정:
   - `[sdk=iphoneos*]` / `[sdk=iphonesimulator*]` → `GratitudeJournal/Supporting/GratitudeJournal-iOS.entitlements`
   - `[sdk=macosx*]` Debug → `…-macOS.entitlements`, Release → `…-macOS-Release.entitlements`
6. Build Settings ▸ **Swift Language Version = Swift 5** (Swift 6 strict 모드에선 일부 경고 정리 필요)
7. (선택) 메뉴 막대 전용 앱으로 시작하려면 Info ▸ `Application is agent (UIElement)` = YES. 기본은 Dock + 메뉴 막대이고, 설정에서 Dock 숨김을 켤 수 있습니다.

### 앱 아이콘

`Resources/Assets.xcassets/AppIcon.appiconset`에 iOS 1024px 1장 + macOS 10개 사이즈가 이미 들어 있습니다. 타깃 ▸ General ▸ **App Icons and Launch Screen ▸ App Icon = `AppIcon`** 인지만 확인하세요.
디자인(색·표정)을 바꾸려면 `Scripts/generate_icon.py` 상단 색상값을 수정하고 `python3 Scripts/generate_icon.py` 재실행.
메뉴 막대 아이콘은 SF Symbol `face.smiling`(템플릿 이미지)을 써서 라이트/다크 메뉴 막대에 자동으로 맞춰집니다.

---

## 4. 데이터 모델 & CloudKit 제약

`GratitudeEntry` — `id`, `createdAt`, `emotionLevel(1~7)`, `gratitudeBody`, `summary?` (+ 내부용 `updatedAt`).

CloudKit 동기화를 켠 SwiftData 모델은 다음을 지켜야 합니다. 어기면 **컨테이너 생성 단계에서 실패**합니다.
- 모든 속성에 기본값 또는 옵셔널 → 그래서 `var id: UUID = UUID()` 형태
- `@Attribute(.unique)` 사용 불가 → UUID로 앱에서 고유성 보장
- 관계는 전부 옵셔널

스키마를 바꿀 때는 **속성 추가만** 하세요(삭제·이름 변경은 이미 배포된 CloudKit 스키마와 충돌).

---

## 5. 동기화 동작 방식

```
[iPhone] 저장 → context.save() → CloudKit export
                                         │  (사용자 개인 iCloud Private DB)
[Mac]   ← 무음 푸시 수신 ← ───────────────┘
         → import → mainContext 자동 병합 → @Query가 목록 갱신
```

- 코드로 직접 업로드/다운로드하지 않습니다. `EntryRepository`가 `save()`만 하면 됩니다.
- 보통 수 초 내 반영. 앱이 백그라운드일 땐 시스템이 시점을 조절하므로 '실시간'은 포그라운드 기준입니다.
- 메인 윈도우·메뉴 막대·빠른 작성 패널이 모두 `AppContainer.shared` **하나**를 쓰므로 같은 Mac 안에서는 즉시 반영됩니다.
- `SyncMonitor`가 `NSPersistentCloudKitContainer.eventChangedNotification`을 구독해 '동기화 중 / 동기화됨 / 오류 / iCloud 로그인 필요'를 표시합니다.
- 충돌 정책: 마지막 저장이 이김(last-writer-wins). 일기는 한 사람이 쓰므로 충분합니다.

**테스트:** 실제 iPhone과 Mac에 같은 Apple ID로 로그인 → 둘 다 Xcode에서 실행(Development 환경). 시뮬레이터는 푸시가 불안정하니 실기기 권장.
**출시 전:** [CloudKit Console](https://icloud.developer.apple.com) ▸ 컨테이너 ▸ Schema ▸ **Deploy Schema Changes to Production**. 안 하면 TestFlight/App Store/dmg 빌드에서 동기화가 안 됩니다.


### iPhone 웹앱 + Mac 앱 동기화 (Supabase, 무료)

iPhone은 웹앱(`web/`), Mac은 네이티브 앱을 쓰고 둘 다 같은 Supabase 데이터베이스를 씁니다. 설정 방법은 아래 **8. iPhone 웹앱** 참고.

---

## 6. 메뉴 막대 + `⌘⇧G` 빠른 작성

- `MenuBarExtra(.window)` — 아이콘 클릭 시 빠른 작성 폼 + 최근 3개 + 앱 열기/설정/종료
- `applicationShouldTerminateAfterLastWindowClosed → false` — 창을 닫아도 상주
- 설정: **로그인 시 자동 실행**(`SMAppService`), **Dock 아이콘 숨기기**(`setActivationPolicy(.accessory)`)
- `GlobalHotKey` — Carbon `RegisterEventHotKey`. 손쉬운 사용 권한 팝업이 없고 샌드박스에서도 동작.
- `QuickEntryPanel` — `.nonactivatingPanel` 플로팅 패널. 다른 앱을 쓰던 중에 바로 위에 떠서 입력되고, 메인 창은 튀어나오지 않습니다. 마우스가 있는 화면 위쪽에 뜨며, 모든 Space와 전체화면 앱 위에도 표시됩니다.
- 패널 단축키: `⌘↩` 저장 · `esc` 닫기 · 바깥 클릭 시 숨김(작성 중 내용 유지)

> ⚠️ `⌘⇧G`는 Finder의 '폴더로 이동'과 같은 조합입니다. 이 앱이 실행 중이면 이 앱이 우선 가져갑니다. 바꾸려면 `AppDelegate`에서 `kVK_ANSI_G`/modifiers를 수정하세요. 사용자가 직접 바꾸게 하려면 [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 패키지로 교체하는 것을 추천합니다.

---

## 7. dmg 빌드 (App Store 밖 배포)

필요: Apple Developer Program(유료) — **CloudKit은 서명 없는 앱에서 동작하지 않습니다.**

1. Xcode ▸ Settings ▸ Accounts에서 팀 추가, Certificates에서 **Developer ID Application** 인증서 생성
2. `Scripts/ExportOptions.plist`의 `YOUR_TEAM_ID` 교체
3. 공증 자격 증명 저장 (앱 암호는 appleid.apple.com에서 발급)
   ```bash
   xcrun notarytool store-credentials "gratitude-notary" \
     --apple-id "you@example.com" --team-id "YOUR_TEAM_ID" --password "xxxx-xxxx-xxxx-xxxx"
   ```
4. 프로젝트 루트(.xcodeproj가 있는 곳)에서
   ```bash
   ./Scripts/build_dmg.sh                  # → build/GratitudeJournal-1.0.dmg
   SKIP_NOTARIZE=1 ./Scripts/build_dmg.sh  # 내 Mac 테스트용
   ```

스크립트 흐름: `xcodebuild archive` → `-exportArchive (developer-id)` → `hdiutil`로 앱 + `/Applications` 바로가기가 담긴 dmg → `codesign` → `notarytool submit --wait` → `stapler staple` → `spctl` 검증.

Release 엔타이틀먼트에 `com.apple.developer.icloud-container-environment = Production`이 들어 있는 이유: Developer ID 앱은 이를 명시해야 App Store/TestFlight iPhone 앱과 **같은 Production 데이터**를 봅니다. 배경이 그려진 예쁜 dmg 창을 원하면 `brew install create-dmg`로 3단계를 대체하세요.

---

## 8. iPhone 웹앱 (설치 없이 '홈 화면에 추가')

```
web/
├─ index.html  styles.css  app.js     # 웹앱 (빌드 과정 없음)
├─ config.js                          # ★ Supabase 주소·키 입력
├─ manifest.webmanifest  sw.js        # 홈 화면 아이콘·오프라인
└─ icons/
supabase/schema.sql                   # ★ DB 테이블·보안 규칙 (한 번 실행)
```

1. **Supabase** (supabase.com, 무료) → New project (Region: Seoul) → **SQL Editor**에 `supabase/schema.sql` 전체 붙여 넣고 Run
2. (선택) Authentication ▸ Sign In / Providers ▸ Email ▸ **Confirm email 끄기** → 가입 즉시 로그인
3. Project Settings ▸ API 의 **Project URL**, **anon public** 키를
   - `web/config.js` 의 `SUPABASE_URL`, `SUPABASE_ANON_KEY`
   - `GratitudeJournal/Services/AppContainer.swift` 의 `SupabaseConfig.url`, `anonKey` 에 붙여 넣기
4. **GitHub Pages**로 올리기: 새 저장소 → `web/` 폴더 **안의 파일들**을 업로드 → Settings ▸ Pages ▸ Branch `main` / `(root)` → 나온 주소(https://아이디.github.io/저장소/)를 iPhone Safari로 열기
5. iPhone Safari: **공유 ▸ 홈 화면에 추가**, 앱에서 계정 만들기
6. Mac 앱: Xcode Build Settings ▸ **Outgoing Network Connections = YES** (App Sandbox ▸ Outgoing Connections) → 설정(⌘,) ▸ 동기화 ▸ 같은 계정으로 로그인

웹앱을 고친 뒤 다시 올릴 때는 `sw.js`의 `VERSION`을 올리면 iPhone에도 새 버전이 반영됩니다.
