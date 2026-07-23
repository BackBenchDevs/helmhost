import Cocoa
import FlutterMacOS

/// Flutter ↔ native About: OS menu asks Dart to show the custom dialog.
enum HelmhostAboutBridge {
  private(set) static var channel: FlutterMethodChannel?

  static func attach(binaryMessenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "helmhost/app", binaryMessenger: binaryMessenger)
    channel = ch
    // Dart owns presentation; native only invokes showAbout.
    ch.setMethodCallHandler { call, result in
      result(FlutterMethodNotImplemented)
    }
  }

  static func requestShowAbout() {
    channel?.invokeMethod("showAbout", arguments: nil)
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    wireAboutMenuItem()
    super.applicationDidFinishLaunching(notification)
  }

  private func wireAboutMenuItem() {
    guard let mainMenu = NSApp.mainMenu else { return }
    for item in mainMenu.items {
      guard let submenu = item.submenu else { continue }
      for sub in submenu.items where sub.title.hasPrefix("About") {
        sub.target = self
        sub.action = #selector(showHelmhostAbout(_:))
        return
      }
    }
  }

  @objc func showHelmhostAbout(_ sender: Any?) {
    HelmhostAboutBridge.requestShowAbout()
  }
}
