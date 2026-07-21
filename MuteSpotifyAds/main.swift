import Cocoa

// Force Serbian (Cyrillic) as the app language
UserDefaults.standard.set(["sr"], forKey: "AppleLanguages")
UserDefaults.standard.synchronize()

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
