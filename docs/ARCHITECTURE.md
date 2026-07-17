# Архитектура MuteSpotifyAds

## Преглед

MuteSpotifyAds је нативна macOS апликација (Cocoa/Swift) која аутоматски утишава рекламе у Spotify десктоп клијенту. Апликација ради као status bar агент (LSUIElement) -- нема Dock икону ни главни прозор, само мени у status bar-у.

## Компоненте

### AppDelegate (`/Users/mprinc/data/development/3rd-party-zontik/sound/MuteSpotifyAds/MuteSpotifyAds/AppDelegate.swift`)

Главна улазна тачка апликације. Одговорна за:

- **UI менаџмент** -- управља status bar менијем (NSStatusItem) и свим menu item-има (checkbox-и за опције)
- **Персистенција подешавања** -- чита/пише корисничка подешавања преко `UserDefaults` (endless private session, restart to skip ads, start Spotify, notifications, song log path)
- **Нотификације** -- шаље macOS нотификације кад се реклама детектује (NSUserNotification)
- **Status bar наслов** -- ажурира status bar икону (☀︎ = нема рекламе, ☂︎ = реклама)
- **Животни циклус** -- иницијализује SpotifyManager при покретању, гаси апликацију кад корисник одлучи

### SpotifyManager (`/Users/mprinc/data/development/3rd-party-zontik/sound/MuteSpotifyAds/MuteSpotifyAds/SpotifyManager.swift`)

Централна бизнис логика апликације. Одговорна за:

- **File System мониторинг** -- прати промјене на Spotify фајловима (`recently_played.bnk` и `ad-state-storage.bnk`) преко FSEventStream API-ја. Ово је кључ ефикасности -- апликација не poll-ује, већ реагује само на промјене фајлова
- **Детекција реклама** -- преко AppleScript-а провјерава Spotify URL тренутне нумере (`spotify:ad` префикс = реклама)
- **Mute/Unmute** -- чува корисничку јачину звука прије мутирања, враћа је кад реклама заврши
- **Restart to skip** -- опционално рестартује Spotify да прескочи рекламу, уз управљање play/pause стањем
- **Private session** -- преко AppleScript-а кликне на "Private Session" у Spotify менију (System Events аутоматизација)
- **Song logging** -- логује информације о свакој нумери у CSV фајл (назив, артист, албум, итд.)
- **Покретање/гашење Spotify-ја** -- контролише животни циклус Spotify клијента преко `NSWorkspace` нотификација и `/usr/bin/open`

### StatusBarTitle (`/Users/mprinc/data/development/3rd-party-zontik/sound/MuteSpotifyAds/MuteSpotifyAds/StatusBarTitle.swift`)

Enum са два стања status bar наслова:
- `.noAd` = `☀︎` (сунце -- све у реду)
- `.ad` = `☂︎` (кишобран -- реклама у току)

### MainMenu.xib (`/Users/mprinc/data/development/3rd-party-zontik/sound/MuteSpotifyAds/MuteSpotifyAds/Base.lproj/MainMenu.xib`)

Interface Builder фајл са дефиницијом status bar менија и свих menu item-а. Повезан са AppDelegate преко IBOutlet/IBAction веза.

## Комуникација између компоненти

```
┌──────────────┐       titleChangeHandler       ┌────────────────┐
│  AppDelegate │ ◄──────── callback ──────────── │ SpotifyManager │
│              │                                 │                │
│ • UI/Menu    │ ─── методе (toggle, start) ──► │ • FS Events    │
│ • StatusBar  │                                 │ • AppleScript  │
│ • UserDefaults│                                │ • Ad detection │
└──────┬───────┘                                 └───────┬────────┘
       │                                                 │
       │ reads                                           │ watches
       ▼                                                 ▼
  UserDefaults                              ~/Library/Application Support/
  (подешавања)                              Spotify/Users/*-user/
                                            ├── recently_played.bnk
                                            └── ad-state-storage.bnk
```

1. **AppDelegate → SpotifyManager**: AppDelegate креира SpotifyManager и прослеђује callback за промјену наслова. Кроз menu item акције (IBAction), директно позива методе SpotifyManager-а.
2. **SpotifyManager → AppDelegate**: SpotifyManager комуницира назад кроз `titleChangeHandler` callback кад се стање промијени (реклама почела/завршила).
3. **SpotifyManager → Spotify**: Комуницира преко AppleScript-а (`/usr/bin/osascript`) за контролу јачине звука, детекцију реклама, play/pause, и private session.
4. **SpotifyManager → File System**: Прати промјене на Spotify кеш фајловима преко macOS FSEventStream API-ја.

## Животни циклус апликације

1. AppDelegate.applicationDidFinishLaunching() иницијализује UI и подешавања
2. Креира SpotifyManager са callback-ом за промјену наслова
3. Учитава сачувана подешавања из UserDefaults
4. SpotifyManager.startWatchingForFileChanges() покреће Spotify (ако је подешено) и FSEventStream мониторинг
5. Кад се Spotify фајл промијени → handleTrackChanged() → провјерава да ли је реклама → mute/unmute
6. Кад корисник затвори Spotify → NSWorkspace нотификација → апликација се гаси (осим ако је restart у току)
