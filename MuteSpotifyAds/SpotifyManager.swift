//
//  SpotifyManager.swift
//  MuteSpotifyAds
//
//  Created by Simon Meusel on 29.05.18.
//  Copyright © 2019 Simon Meusel. All rights reserved.
//

import Cocoa

class SpotifyManager: NSObject {
    
    static let appleScriptSpotifyPrefix = "tell application \"Spotify\" to "
    
    var titleChangeHandler: ((StatusBarTitle) -> Void)
    var fileEventStream: FSEventStreamRef?
    
    var endlessPrivateSessionEnabled = false
    var restartToSkipAdsEnabled = false
    var startSpotifyInBackground = false
    var songLogPath: String? = nil
    var startSpotify = false
    
    /**
     * Volume before mute, between 0 and 100
     */
    var spotifyUserVolume = 0
    /**
     * Whether spotify is being muted
     */
    var muted = false
    /**
     * Whether Spotify is getting restarted
     */
    var isRestarting = false

    var lastSongSpotifyURL: String = ""
    
    init(titleChangeHandler: @escaping ((StatusBarTitle) -> Void)) {
        self.titleChangeHandler = titleChangeHandler
        
        super.init()
        
        // Stop this application when Spotify gets closed
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil, using: {
            notification in
            
            if self.startSpotify {
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as! NSRunningApplication
                if (app.bundleIdentifier == "com.spotify.client") {
                    self.handleSpotifyQuit()
                }
            }
        })
    }
    
    func handleSpotifyQuit() {
        if (isRestarting) {
            self.ensureSpotifyPlays(attempt: 0, lastStateBeforePlay: nil)
        } else {
            NSApplication.shared.terminate(self)
        }
    }

    /**
     * Retry play до 15s. Ако корисник сам промијени стање — одустани.
     */
    func ensureSpotifyPlays(attempt: Int, lastStateBeforePlay: String?) {
        let maxAttempts = 15 // 15 x 1s = 15s

        // Провјери тренутно стање ПРИЈЕ play-а
        let stateBefore = getSpotifyPlayerState()

        // Ако имамо претходно стање и разликује се од очекиваног —
        // корисник је интереаговао (нпр. ручно паузирао или покренуо)
        if let lastState = lastStateBeforePlay {
            // Послије нашег play-а, стање је требало бити "playing".
            // Ако је сад нешто друго (нпр. "paused") а ми смо послали play —
            // значи корисник је у међувремену паузирао. Одустани.
            if lastState == "playing" && stateBefore == "paused" {
                self.finishRestart()
                return
            }
        }

        if isSpotifyPlaying() {
            // Spotify свира — готово
            self.sendSpotifyToBack()
            self.finishRestart()
            return
        }

        if attempt >= maxAttempts {
            // Истекло вријеме — одустани
            self.finishRestart()
            return
        }

        // Пошаљи play
        self.spotifyPlay()
        self.sendSpotifyToBack()

        let stateAfterPlay = getSpotifyPlayerState()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            self.ensureSpotifyPlays(attempt: attempt + 1, lastStateBeforePlay: stateAfterPlay)
        })
    }

    func finishRestart() {
        self.sendSpotifyToBack()
        self.titleChangeHandler(.noAd)
        self.isRestarting = false
    }
    
    func getSpotifyPlayerState() -> String {
        return runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "(get player state)").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isSpotifyPaused() -> Bool {
        return getSpotifyPlayerState() == "paused"
    }

    func isSpotifyPlaying() -> Bool {
        return getSpotifyPlayerState() == "playing"
    }
    
    func startWatchingForFileChanges() {
        if startSpotify {
            DispatchQueue.global(qos: .default).async {
                self.startSpotify(foreground: !self.startSpotifyInBackground)
                _ = self.handleTrackChanged()
            }
        }
        
        var path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        path.appendPathComponent("Spotify")
        path.appendPathComponent("Users")
        
        let enumerator = FileManager.default.enumerator(at: path, includingPropertiesForKeys: [], options: [.skipsSubdirectoryDescendants], errorHandler: nil)
        
        var files: [String] = []
        
        while let file = enumerator?.nextObject() as? URL {
            if file.path.hasSuffix("-user") {
                files.append(file.appendingPathComponent("recently_played.bnk.tmp").path)
                files.append(file.appendingPathComponent("ad-state-storage.bnk.tmp").path)
                files.append(file.appendingPathComponent("recently_played.bnk").path)
                files.append(file.appendingPathComponent("ad-state-storage.bnk").path)
            }
        }
        
        // Create file watcher with context
        var context = FSEventStreamContext(version: 0, info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), retain: nil, release: nil, copyDescription: nil)
        fileEventStream = FSEventStreamCreate(kCFAllocatorDefault, {
            _, info, _, _, _, _ in
            
            DispatchQueue.global(qos: .default).async {
                _ = Unmanaged<SpotifyManager>.fromOpaque(
                    info!).takeUnretainedValue().handleTrackChanged()
            }
        }, &context, files as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0, UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))
        
        FSEventStreamScheduleWithRunLoop(fileEventStream!, RunLoop.current.getCFRunLoop(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(fileEventStream!)
    }
    
    func startSpotify(foreground: Bool) {
        let process = Process()
        // Open application with bundle identifier
        process.launchPath = "/usr/bin/open"
        
        var arguments: [String] = []
        if (!foreground) {
            arguments += ["--hide", "--background"]
        }
        arguments += ["-b", "com.spotify.client"]
        
        process.arguments = arguments
        process.launch()
        process.waitUntilExit()
    }
    
    /**
     * Enables private Spotify session
     */
    func enablePrivateSession() {
        // See https://stackoverflow.com/questions/51068410/osx-tick-menu-bar-checkbox/51068836#51068836
        let script = """
            tell application \"System Events\" to tell process \"Spotify\"
                tell menu bar item 2 of menu bar 1
                    tell menu item \"Private Session\" of menu 1
                        set isChecked to value of attribute \"AXMenuItemMarkChar\" is \"✓\"
                        if not isChecked then click it
                    end tell
                end tell
            end tell
            """
        _ = runAppleScript(script: script)
    }
    
    /**
     * Disables private Spotify session
     */
    func disablePrivateSession() {
        // See https://stackoverflow.com/questions/51068410/osx-tick-menu-bar-checkbox/51068836#51068836
        let script = """
            tell application \"System Events\" to tell process \"Spotify\"
                tell menu bar item 2 of menu bar 1
                    tell menu item \"Private Session\" of menu 1
                        set isChecked to value of attribute \"AXMenuItemMarkChar\" is \"✓\"
                        if isChecked then click it
                    end tell
                end tell
            end tell
            """
        _ = runAppleScript(script: script)
    }
    
    /**
     * Checks for a currently playing ad
     *
     * Returns true if spotify got muted or unmuted, false otherwise
     */
    func handleTrackChanged() -> Bool {
        var changed = false
        
        if isSpotifyAdPlaying() {
            if !restartToSkipAdsEnabled && !muted {
                spotifyUserVolume = getSpotifyVolume()
                setSpotifyVolume(volume: 0)
                muted = true
                titleChangeHandler(.ad)
                changed = true
            }
            if restartToSkipAdsEnabled {
                restartSpotify()
            }
        } else {
            // Reactivate spotify if ad is done
            if muted {
                // Don't change volume if user manually changed it
                if getSpotifyVolume() == 0 && spotifyUserVolume != 0 {
                    setSpotifyVolume(volume: spotifyUserVolume)
                }
                muted = false
                titleChangeHandler(.noAd)
                changed = true
            }
        }
        
        if endlessPrivateSessionEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2), execute: {
                self.enablePrivateSession()
            })
        }
        
        if songLogPath != nil {
            logSong()
        }
        
        return changed
    }
    
    func setSpotifyVolume(volume: Int) {
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "set sound volume to \(volume)")
    }
    
    /**
     * Gets current spotify volume
     */
    func getSpotifyVolume() -> Int {
        let volume = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "(get sound volume)")
        // Convert to number
        return Int(volume.split(separator: "\n")[0])!
    }
    
    /**
     * Checks whether an ad is currently playing
     *
     * This is done by checking the spoify url's prifix
     */
    func isSpotifyAdPlaying() -> Bool {
        let spotifyURL = getCurrentSongSpotifyURL()
        return spotifyURL.starts(with: "spotify:ad")
    }
    
    func getCurrentSongSpotifyURL() -> String {
        return runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "(get spotify url of current track)")
    }
    
    func restartSpotify() {
        isRestarting = true
        titleChangeHandler(.ad)
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "quit")
        startSpotify(foreground: false)
    }
    
    func quitSpotify() {
        titleChangeHandler(.ad)
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "quit")
    }
    
    /**
     * Runs the given apple script and passes logs to completion handler
     */
    func runAppleScript(script: String) -> String {
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        process.launch()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.availableData
        return String(data: data, encoding: String.Encoding.utf8)!
    }
    
    func toggleSpotifyPlayPause() {
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "playpause")
    }

    func spotifyNextTrack() {
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "next track")
    }

    func spotifyPreviousTrack() {
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "previous track")
    }

    func spotifyRewind15() {
        _ = runAppleScript(script: """
            tell application "Spotify"
                set pos to player position
                if pos > 15 then
                    set player position to (pos - 15)
                else
                    set player position to 0
                end if
            end tell
        """)
    }

    func spotifyRestartTrack() {
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "set player position to 0")
    }
    
    /// UNUSED: Чува се за потенцијални fallback ако app.hide() не буде довољан.
    /// sendSpotifyToBack() тренутно користи app.hide() и не зависи од овог.
    var appBeforePlay: NSRunningApplication?

    func spotifyPlay() {
        // Сачувај frontmost САМО ако није Spotify (да fallback не активира Spotify назад)
        let current = NSWorkspace.shared.frontmostApplication
        if current?.bundleIdentifier != "com.spotify.client" {
            appBeforePlay = current
        }
        _ = runAppleScript(script: SpotifyManager.appleScriptSpotifyPrefix + "play")
    }

    /// Сакрива Spotify у позадину (Cmd+H) без уклањања из Cmd+Tab.
    /// Види ARCHITECTURE.md "Lessons Learned > Spotify refocus" за историју неуспјелих покушаја.
    func sendSpotifyToBack() {
        // app.hide() = Cmd+H = исти механизам као open --hide --background при покретању
        // За разлику од "set visible to false", Spotify ОСТАЈЕ у Cmd+Tab
        // За разлику од "set frontmost to false", ово ПОУЗДАНО ради без timing проблема
        for app in NSWorkspace.shared.runningApplications {
            if app.bundleIdentifier == "com.spotify.client" {
                app.hide()
                break
            }
        }
    }
    
    /**
     * Log information about the current song to the song log file
     */
    func logSong() {
        let currentSongSpotifyURL = getCurrentSongSpotifyURL()
        if (lastSongSpotifyURL == currentSongSpotifyURL) {
            return
        }
        lastSongSpotifyURL = currentSongSpotifyURL
        
        var script = "set o to \"\"\n"
        let songProperties = ["name", "artist", "album", "disc number", "duration", "played count", "track number", "popularity", "id", "artwork url", "album artist", "spotify url"]
        for property in songProperties {
            script += "tell application \"Spotify\"\nset o to o & \"\n\" & (get " + property + " of current track)\nend tell\n"
        }
        
        var logEntry = runAppleScript(script: script).replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: ",")
        if logEntry == "" {
            return
        }
        logEntry.removeFirst()
        logEntry.removeLast()
        logEntry += "," + Date().description + "\n"
        
        if !FileManager.default.fileExists(atPath: songLogPath!) {
            FileManager.default.createFile(atPath: songLogPath!, contents: (songProperties.joined(separator: ",") + ",date\n").data(using: .utf8), attributes: nil)
        }
        
        if let fileUpdater = try? FileHandle(forUpdating: URL(fileURLWithPath: songLogPath!)) {
            fileUpdater.seekToEndOfFile()
            fileUpdater.write(logEntry.data(using: .utf8)!)
            fileUpdater.closeFile()
        }
    }
    
}
