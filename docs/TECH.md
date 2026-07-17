# Технички детаљи MuteSpotifyAds

## Стек технологија

| Технологија | Верзија | Сврха |
|---|---|---|
| Swift | 5.0 | Програмски језик |
| Cocoa (AppKit) | macOS SDK | UI framework за macOS десктоп апликације |
| Xcode | 11.5+ (LastUpgradeCheck = 1150) | Build систем и IDE |
| macOS deployment target | 10.12 (Sierra) | Минимална подржана верзија macOS-а |

## Екстерне зависности

Пројекат **нема екстерних зависности**. Све је имплементирано преко нативних macOS API-ја. У пројекту постоји референца на `EonilFileSystemEvents.framework` (Carthage), али се тренутно не линкује у build фази -- замијењен је директним коришћењем `FSEventStream` C API-ја.

## Кључне технологије и API-ји

### FSEventStream (Core Services)

- **Документација**: File System Events Programming Guide (Apple Developer)
- **Зашто**: Омогућава ефикасно праћење промјена на фајл систему без polling-а. Апликација прати промјене на Spotify кеш фајловима (`recently_played.bnk`, `ad-state-storage.bnk`) и реагује само кад се фајл измијени.
- **Имплементација**: `SpotifyManager.startWatchingForFileChanges()` (`/Users/mprinc/data/development/3rd-party-zontik/sound/MuteSpotifyAds/MuteSpotifyAds/SpotifyManager.swift:77`) -- креира FSEventStream са `kFSEventStreamCreateFlagFileEvents` за прецизно праћење појединачних фајлова.
- **Ефикасност**: 0% CPU у idle стању, ~0.4% CPU само кад се нумера промијени.

### AppleScript (OSA)

- **Документација**: Open Scripting Architecture (Apple Developer)
- **Зашто**: Једини начин за програмску интеракцију са Spotify десктоп клијентом на macOS-у. Spotify излаже AppleScript речник за контролу плејера.
- **Имплементација**: `SpotifyManager.runAppleScript()` (`/Users/mprinc/data/development/3rd-party-zontik/sound/MuteSpotifyAds/MuteSpotifyAds/SpotifyManager.swift:264`) -- покреће `/usr/bin/osascript` као екстерни процес.
- **Употреба**:
  - `tell application "Spotify" to (get spotify url of current track)` -- детекција реклама
  - `tell application "Spotify" to (get sound volume)` / `set sound volume to X` -- контрола јачине звука
  - `tell application "Spotify" to (get player state)` -- провјера play/pause стања
  - `tell application "System Events"` -- контрола Private Session преко UI аутоматизације

### NSStatusItem (AppKit)

- **Документација**: NSStatusItem (Apple Developer)
- **Зашто**: Стандардни macOS API за креирање status bar ставки. Апликација живи искључиво у status bar-у.
- **Имплементација**: `AppDelegate.statusItem` (`/Users/mprinc/data/development/3rd-party-zontik/sound/MuteSpotifyAds/MuteSpotifyAds/AppDelegate.swift:30`) -- креира status item са променљивом ширином и текстуалним насловом.

### NSWorkspace нотификације

- **Документација**: NSWorkspace (Apple Developer)
- **Зашто**: За детекцију кад корисник затвори Spotify. Апликација треба да се угаси кад Spotify није покренут.
- **Имплементација**: `SpotifyManager.init()` (`/Users/mprinc/data/development/3rd-party-zontik/sound/MuteSpotifyAds/MuteSpotifyAds/SpotifyManager.swift:44`) -- ослушкује `didTerminateApplicationNotification` и провјерава `bundleIdentifier == "com.spotify.client"`.

### UserDefaults

- **Документација**: UserDefaults (Apple Developer)
- **Зашто**: Стандардни macOS механизам за персистенцију корисничких подешавања. Лагана и једноставна key-value складишница.
- **Кључеви**: `EndlessPrivateSession`, `RestartToSkipAds`, `StartSpotify`, `Notifications`, `SongLogPath`

### Interface Builder (XIB)

- **Документација**: Interface Builder (Apple Developer)
- **Зашто**: Стандардни Apple алат за визуелно дефинисање UI-ја. MainMenu.xib дефинише цијели status bar мени декларативно.
- **Локализације**: en, de, zh-Hans, tr, it, es -- свака у засебном `.lproj` директоријуму са `MainMenu.strings` фајлом.

## Build конфигурација

- **Signing**: `CODE_SIGN_IDENTITY = "-"` (ad-hoc signing, без Apple Developer сертификата)
- **Hardened Runtime**: Укључен (`ENABLE_HARDENED_RUNTIME = YES`)
- **Sandbox**: Искључен (`com.apple.Sandbox.enabled = 0`) -- неопходно за AppleScript и FS Events
- **LSUIElement**: `true` у Info.plist -- апликација нема Dock икону, живи само у status bar-у
- **Bundle ID**: `de.simonmeusel.MuteSpotifyAds`

## Покретање пројекта

### Предуслови

- macOS 10.12+ (тестирано до macOS Catalina 10.15.1)
- Xcode 11+ (потребан је пуни Xcode.app, не само Command Line Tools, због XIB фајлова и Asset Catalog-а)
- Spotify десктоп клијент инсталиран

### Build и покретање

```bash
# Преко Xcode-а (препоручено):
open MuteSpotifyAds.xcodeproj
# Затим: Product → Run (⌘R)

# Преко command line-а (потребан Xcode.app):
xcodebuild -project MuteSpotifyAds.xcodeproj \
  -scheme MuteSpotifyAds \
  -configuration Debug \
  build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO

# Покретање build-ованог .app:
open build/Build/Products/Debug/MuteSpotifyAds.app
```

### Инсталација преко Homebrew

```bash
brew cask install mutespotifyads
```
