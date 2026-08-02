# Архитектура УкротиСпоти (MuteSpotifyAds)

## Преглед

Нативна macOS апликација (Cocoa/Swift) која аутоматски утишава или прескаче рекламе у Spotify десктоп клијенту. Ради као status bar агент (LSUIElement) -- нема Dock икону ни главни прозор, само мени у status bar-у.

## Компоненте

### main.swift (`/Users/mprinc/data/development/3rd-party-zontik/sound/MuteSpotifyAds/MuteSpotifyAds/main.swift`)

Entry point апликације. Форсира српски (ћирилица) као језик апликације постављањем `AppleLanguages` у UserDefaults **прије** учитавања NIB-а. Замјењује `@NSApplicationMain` атрибут.

### AppDelegate (`/Users/mprinc/data/development/3rd-party-zontik/sound/MuteSpotifyAds/MuteSpotifyAds/AppDelegate.swift`)

UI слој апликације. Одговорна за:

- **Status bar мени** -- управља NSStatusItem и свим menu item-има (checkbox прекидачи за опције)
- **Персистенција подешавања** -- чита/пише UserDefaults (private session, restart to skip, start Spotify, start in background, notifications, song log path)
- **Нотификације** -- шаље macOS нотификације кад се реклама детектује
- **Status bar наслов** -- ажурира икону (☀︎ = нема рекламе, ☂︎ = реклама)
- **Константе** -- `appName = "УкротиСпоти"` као једно мјесто за име апликације
- **Тест** -- `simulateAdRestart` за ручно тестирање restart flow-а

### SpotifyManager (`/Users/mprinc/data/development/3rd-party-zontik/sound/MuteSpotifyAds/MuteSpotifyAds/SpotifyManager.swift`)

Централна бизнис логика. Одговорна за:

- **File System мониторинг** -- прати промјене на Spotify кеш фајловима преко FSEventStream API-ја (event-driven, не polling)
- **Детекција реклама** -- провјерава Spotify URL тренутне нумере (`spotify:ad` префикс)
- **Mute/Unmute** -- чува јачину звука прије мутирања, враћа кад реклама заврши
- **Restart to skip** -- гаси и поново покреће Spotify да прескочи рекламу
- **Window management** -- `sendSpotifyToBack()` спречава Spotify да краде фокус при рестарту
- **Private session** -- преко System Events AppleScript-а одржава приватну сесију
- **Song logging** -- логује нумере у CSV фајл
- **Животни циклус Spotify-ја** -- покретање, гашење, детекција гашења преко NSWorkspace нотификација

### StatusBarTitle (`/Users/mprinc/data/development/3rd-party-zontik/sound/MuteSpotifyAds/MuteSpotifyAds/StatusBarTitle.swift`)

Enum са два стања status bar наслова:
- `.noAd` = `☀︎` (сунце -- нормално пуштање)
- `.ad` = `☂︎` (кишобран -- реклама детектована)

### MainMenu.xib (`/Users/mprinc/data/development/3rd-party-zontik/sound/MuteSpotifyAds/MuteSpotifyAds/Base.lproj/MainMenu.xib`)

Interface Builder фајл са дефиницијом status bar менија. Повезан са AppDelegate преко IBOutlet/IBAction веза. Локализован на 7 језика (sr, en, de, es, it, tr, zh-Hans).

## Комуникација између компоненти

```
┌────────────┐     titleChangeHandler      ┌────────────────┐
│ AppDelegate │ ◄────── callback ────────── │ SpotifyManager │
│             │                            │                │
│ • UI/Menu   │ ── методе (toggle, ...) ─► │ • FS Events    │
│ • StatusBar │                            │ • AppleScript  │
│ • Defaults  │                            │ • Ad detection │
│ • Тест      │                            │ • Window mgmt  │
└─────┬───────┘                            └──┬─────────┬───┘
      │                                       │         │
      │ reads/writes                           │watches  │controls
      ▼                                        ▼         ▼
 UserDefaults                    ~/Library/App Support/  Spotify.app
 (подешавања)                    Spotify/Users/*-user/   (AppleScript)
                                 ├── recently_played.bnk
                                 └── ad-state-storage.bnk
```

## Детекција реклама

```
Spotify мијења фајл
        │
        ▼
FSEventStream детектује промјену
        │
        ▼
handleTrackChanged()
        │
        ├── isSpotifyAdPlaying()? ── ДА ──┐
        │                                  │
        │                    ┌─────────────┤
        │                    │             │
        │           restartToSkip?    само mute?
        │                    │             │
        │                    ▼             ▼
        │           restartSpotify()  setVolume(0)
        │                    │        titleChange(.ad)
        │                    │
        │                    ▼
        │           (види "Restart flow" испод)
        │
        ├── НЕ (нормална нумера) ──┐
        │                          │
        │                   muted? ── ДА → врати јачину
        │                          │       titleChange(.noAd)
        │                          │
        │                   endlessPrivateSession? ── ДА → enablePrivateSession()
        │                          │
        └── songLog? ── ДА → logSong()
```

## Restart flow (прескакање реклама)

Ово је најкомплекснији дио апликације. Два метода сарађују:

```
restartSpotify()                          handleSpotifyQuit()
═══════════════                           ═══════════════════
Позива се кад се                          Позива се кад macOS
детектује реклама.                        јави да је Spotify умро.
                                          isRestarting флег одлучује:
1. isRestarting = true                    
2. titleChange(.ad)                       isRestarting == true?
3. quit Spotify (AppleScript) ─────────►  │
4. start Spotify (--hide --background)    │  ДА: Spotify се рестартује
   (готово, нема тајмера)                 │  ├── play (AppleScript)
                                          │  ├── sendSpotifyToBack()
                                          │  ├── паузиран? → чекај 1s → понови
                                          │  └── свира! → sendSpotifyToBack()
                                          │              → titleChange(.noAd)
                                          │              → isRestarting = false
                                          │
                                          │  НЕ: Корисник затворио Spotify
                                          │  └── terminate(self)
                                          │      (угаси и нашу апликацију)
```

**Кључне одлуке:**
- `restartSpotify()` само гаси и покреће Spotify -- нема тајмере ни play логику
- `handleSpotifyQuit()` преузима сву play + window management логику
- Један пут, нема паралелних тајмера, нема трке
- `isRestarting` флег разликује "ми рестартујемо" од "корисник затворио"

## Window management (sendSpotifyToBack)

Спречава Spotify да краде фокус при рестарту:

```
sendSpotifyToBack()
        │
        ├── Spotify НИЈЕ frontmost? → не ради ништа
        │   (корисник је већ Cmd+Tab-овао, не дирај)
        │
        ├── Spotify ЈЕСТЕ frontmost:
        │   │
        │   ▼
        │   set frontmost of Spotify to false
        │   (macOS сам активира сљедећу апликацију у стеку)
        │   │
        │   ▼ (200ms касније)
        │   │
        │   ├── Spotify ВИШЕ НИЈЕ frontmost? → готово
        │   │
        │   └── Spotify И ДАЉЕ frontmost? (fallback)
        │       → пронађи прву видљиву апликацију
        │       → activate њу
```

## Животни циклус апликације

```
main.swift                  AppDelegate                    SpotifyManager
══════════                  ═══════════                    ══════════════
AppleLanguages=sr
        │
        ▼
NSApplicationMain()
        │
        ▼
                    applicationDidFinishLaunching()
                    ├── setStatusBarTitle(.noAd)
                    ├── прикажи верзију у менију
                    ├── креирај SpotifyManager(callback)
                    ├── учитај подешавања из UserDefaults
                    │   ├── endlessPrivateSession
                    │   ├── restartToSkipAds
                    │   ├── startSpotify
                    │   ├── startSpotifyInBackground
                    │   ├── notifications
                    │   └── songLogPath
                    └── startWatchingForFileChanges() ────► покрени Spotify
                                                           покрени FSEventStream
                                                                   │
                                                           ┌───────┘
                                                           │ (event loop)
                                                           ▼
                                                    фајл промијењен
                                                           │
                                                           ▼
                                                    handleTrackChanged()
                                                    (детекција + акција)
```

## Подешавања (UserDefaults кључеви)

| Кључ | Тип | Default | Опис |
|---|---|---|---|
| `EndlessPrivateSession` | Bool | false | Одржава приватну сесију укљученом |
| `RestartToSkipAds` | Bool | false | Рестартуј Spotify умјесто мутирања |
| `StartSpotify` | Bool | true | Аутоматски покрени Spotify |
| `StartSpotifyInBackground` | Bool | false | Покрени Spotify у позадини (--hide --background) |
| `Notifications` | Bool | true | Прикажи macOS нотификације за рекламе |
| `SongLogPath` | String? | nil | Путања до CSV фајла за логовање нумера |

## Lessons Learned

### Spotify refocus — неуспјели покушаји

При рестарту Spotify-ја (ad-skip), Spotify краде фокус од корисникове активне апликације. Овдје су сви покушаји рјешења и зашто су пропали:

| # | Приступ | Проблем |
|---|---|---|
| 1 | `set visible to false` | Потпуно сакрива Spotify — нестаје из Cmd+Tab и Mission Control. Корисник га не може пронаћи. |
| 2 | `set frontmost to false` + `activate(previousApp)` сачуван прије quit-а (7s раније) | Ако корисник Cmd+Tab-ује у међувремену, `previousApp` је застарјела → активира погрешну апликацију. |
| 3 | Исто као #2 али провјера `if currentFront == spotify` | И даље користи застарјелу `previousApp` за activate. |
| 4 | `sendSpotifyToBack()` само на крају restartSpotify (t=7s), уклоњен из handleSpotifyQuit | handleSpotifyQuit позива play без sendToBack → Spotify остаје front 5+ секунди. |
| 5 | `sendSpotifyToBack()` послије сваког play (и handleSpotifyQuit и restartSpotify) | Два паралелна пута (restartSpotify тајмери + handleSpotifyQuit retry) стварају "врзино коло" — борба за фокус са корисниковим Cmd+Tab. |
| 6 | `restorePreviousApp()` — activate само ако Spotify frontmost, само на крају | `set frontmost to false` сам по себи не враћа фокус поуздано. Треба и activate. |
| 7 | `set frontmost to false` + fallback: итерирај `runningApplications`, activate прву видљиву | `runningApplications` НИЈЕ сортиран по Z-order стеку → активира Терминал умјесто VS Code. |
| 8 | Само `set frontmost to false`, без fallback-а | Spotify остаје front — `set frontmost to false` не ради поуздано сам. |

**Кључни увиди:**
- `set frontmost to false` сам по себи НЕ гарантује да ће macOS активирати другу апликацију
- `previousFrontmostApp` сачуван прије quit-а застаријева за 5-10s — корисник може промијенити фокус
- `NSWorkspace.shared.runningApplications` НЕ враћа Z-order — не можемо знати ко је "одмах иза"
- Позивање activate послије СВАКОГ play ствара борбу за фокус ако корисник истовремено Cmd+Tab-ује
- Два паралелна пута (restartSpotify тајмери + handleSpotifyQuit retry) компликују ствари

**Исправан приступ:**
Сачувати frontmost апликацију **непосредно прије** сваког `spotifyPlay()` позива (не прије quit-а). Тако увијек имамо тренутно тачну апликацију. Послије play-а, ако Spotify украо фокус — activate сачувану. Ако корисник у међувремену промијенио фокус (Cmd+Tab) — не дирај.

## Toggle шаблон (додавање новог подешавања)

Сваки toggle прати исти шаблон:

1. `SpotifyManager` -- property: `var myFeature = false`
2. `AppDelegate` -- UserDefaults кључ: `let myFeatureKey = "MyFeature"`
3. `AppDelegate` -- IBOutlet: `@IBOutlet weak var myFeatureCheckbox: NSMenuItem!`
4. `AppDelegate` -- IBAction: `toggleMyFeature(_:)` (toggle property + state + save)
5. `AppDelegate` -- `applicationDidFinishLaunching`: учитај из UserDefaults
6. `MainMenu.xib` -- `<menuItem>` са `<action selector>` и `<outlet>` connection
7. Локализације -- `"ObjectID.title"` у свих 7 `.strings` фајлова
