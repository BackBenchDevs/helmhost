import Carbon
import Cocoa
import FlutterMacOS

/// CGEventTap exclusive keyboard grab → MethodChannel helmhost/exclusive_grab.
///
/// Printable keysyms follow TigerVNC: layout-resolved character (Shift→A / !),
/// not Shift + unshifted base. Local viewer chords (⌘V paste, ⌘C/X consume)
/// are reported to Dart instead of forwarded as Super+letter.
enum ExclusiveGrabBridge {
  private static var channel: FlutterMethodChannel?
  private static var tap: CFMachPort?
  private static var runLoopSource: CFRunLoopSource?
  private static var active = false
  private static var releaseArmed = false
  /// keyCode → keysym at press (release must match; layout may differ after Shift-up).
  private static var downKeysyms: [Int64: Int] = [:]

  static func attach(binaryMessenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(
      name: "helmhost/exclusive_grab",
      binaryMessenger: binaryMessenger
    )
    channel = ch
    ch.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        let ok = start()
        if ok {
          result(nil)
        } else {
          result(
            FlutterError(
              code: "tap_failed",
              message: "CGEventTapCreate failed (grant Accessibility to Helmhost)",
              details: nil
            )
          )
        }
      case "stop":
        stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @discardableResult
  private static func start() -> Bool {
    if tap != nil {
      active = true
      return true
    }
    releaseArmed = false
    let mask =
      (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) |
      (1 << CGEventType.flagsChanged.rawValue)
    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(mask),
        callback: { (_, type, event, _) -> Unmanaged<CGEvent>? in
          return ExclusiveGrabBridge.handle(type: type, event: event)
        },
        userInfo: nil
      )
    else {
      return false
    }
    tap = eventTap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    active = true
    return true
  }

  private static func stop() {
    active = false
    releaseArmed = false
    downKeysyms.removeAll()
    if let eventTap = tap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
    }
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
    runLoopSource = nil
    tap = nil
  }

  private static func handle(
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap = tap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }
    guard active else {
      return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let isDown: Bool
    switch type {
    case .keyDown:
      isDown = true
    case .keyUp:
      isDown = false
    case .flagsChanged:
      isDown = modifierDown(keyCode: keyCode, flags: flags)
    default:
      return Unmanaged.passUnretained(event)
    }

    // Right Command alone = release grab (do not forward).
    if keyCode == 54 {  // kVK_RightCommand
      if isDown {
        releaseArmed = true
      } else if releaseArmed {
        releaseArmed = false
        DispatchQueue.main.async {
          channel?.invokeMethod("releaseChord", arguments: nil)
        }
      }
      return nil
    }
    if isDown {
      releaseArmed = false
    }

    // Viewer-local chords (TigerVNC): ⌘V paste, ⌘C/⌘X consume — not Super+letter.
    if isDown, type == .keyDown,
      let kind = localShortcutKind(keyCode: keyCode, flags: flags)
    {
      DispatchQueue.main.async {
        channel?.invokeMethod("localShortcut", arguments: ["kind": kind])
      }
      return nil
    }

    if let keysym = resolveKeysym(keyCode: keyCode, event: event, type: type) {
      let emit: Int
      if isDown {
        downKeysyms[keyCode] = keysym
        emit = keysym
      } else if let pressed = downKeysyms.removeValue(forKey: keyCode) {
        emit = pressed
      } else {
        emit = keysym
      }
      let args: [String: Any] = [
        "keysym": emit,
        "down": isDown,
        "physical": Int(keyCode),
      ]
      DispatchQueue.main.async {
        channel?.invokeMethod("key", arguments: args)
      }
    } else if !isDown, let pressed = downKeysyms.removeValue(forKey: keyCode) {
      // Translate failed on up — still release the press keysym.
      let args: [String: Any] = [
        "keysym": pressed,
        "down": false,
        "physical": Int(keyCode),
      ]
      DispatchQueue.main.async {
        channel?.invokeMethod("key", arguments: args)
      }
    }
    return nil
  }

  private static func localShortcutKind(keyCode: Int64, flags: CGEventFlags) -> String? {
    let cmd = flags.contains(.maskCommand)
    let ctrl = flags.contains(.maskControl)
    let shift = flags.contains(.maskShift)
    // Never steal Control chords (remote terminal).
    if ctrl && !cmd { return nil }
    if cmd && keyCode == 9 { return "paste" }  // V
    if cmd && (keyCode == 8 || keyCode == 7) { return "consume" }  // C / X
    if shift && !cmd && keyCode == 114 { return "paste" }  // Insert (ANSI)
    return nil
  }

  private static func modifierDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
    switch keyCode {
    case 54, 55:
      return flags.contains(.maskCommand)
    case 59, 62:
      return flags.contains(.maskControl)
    case 56, 60:
      return flags.contains(.maskShift)
    case 58, 61:
      return flags.contains(.maskAlternate)
    default:
      return false
    }
  }

  /// TigerVNC-style: special keys from table; printables via UCKeyTranslate.
  private static func resolveKeysym(
    keyCode: Int64,
    event: CGEvent,
    type: CGEventType
  ) -> Int? {
    if let special = specialKeysym(keyCode: keyCode) {
      return special
    }
    if type == .flagsChanged {
      return specialKeysym(keyCode: keyCode)
    }
    return unicodeKeysym(keyCode: UInt16(keyCode), flags: event.flags)
  }

  /// Layout-resolved printable via UCKeyTranslate (Caps/Shift/Option).
  /// Cmd/Ctrl are omitted so chords don't yield control characters.
  private static func unicodeKeysym(keyCode: UInt16, flags: CGEventFlags) -> Int? {
    guard let unmanaged = TISCopyCurrentKeyboardLayoutInputSource() else {
      return nil
    }
    let source = unmanaged.takeRetainedValue()
    guard
      let uchrCF = TISGetInputSourceProperty(
        source, kTISPropertyUnicodeKeyLayoutData)
    else {
      return nil
    }
    let data = unsafeBitCast(uchrCF, to: CFData.self)
    guard let layoutPtr = CFDataGetBytePtr(data) else { return nil }
    let layout = UnsafePointer<UCKeyboardLayout>(OpaquePointer(layoutPtr))

    // Carbon modifier high-byte for UCKeyTranslate (TigerVNC KeyboardMacOS).
    var carbon: UInt32 = 0
    if flags.contains(.maskShift) { carbon |= UInt32(shiftKey) }
    if flags.contains(.maskAlphaShift) { carbon |= UInt32(alphaLock) }
    if flags.contains(.maskAlternate) { carbon |= UInt32(optionKey) }
    let modByte = (carbon >> 8) & 0xFF

    var dead: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 8)
    var len = 0
    var err = UCKeyTranslate(
      layout,
      keyCode,
      UInt16(kUCKeyActionDown),
      modByte,
      UInt32(LMGetKbdType()),
      OptionBits(kUCKeyTranslateNoDeadKeysBit),
      &dead,
      chars.count,
      &len,
      &chars
    )
    // Dead key: press again to get spacing equivalent (TigerVNC).
    if err == noErr, dead != 0 {
      err = UCKeyTranslate(
        layout,
        keyCode,
        UInt16(kUCKeyActionDown),
        modByte,
        UInt32(LMGetKbdType()),
        0,
        &dead,
        chars.count,
        &len,
        &chars
      )
    }
    guard err == noErr, len > 0 else { return nil }
    let scalar = UInt32(chars[0])
    if scalar < 0x20 || (scalar >= 0x7f && scalar < 0xa0) {
      return nil
    }
    return ucsToKeysym(scalar)
  }

  private static func ucsToKeysym(_ u: UInt32) -> Int {
    if u >= 0x20 && u <= 0x7e { return Int(u) }
    if u >= 0xa0 && u <= 0xff { return Int(u) }
    return Int(0x0100_0000 | u)
  }

  private static func specialKeysym(keyCode: Int64) -> Int? {
    switch keyCode {
    case 36: return 0xff0d  // return
    case 48: return 0xff09  // tab
    case 49: return 0x0020  // space (also via unicode)
    case 51: return 0xff08  // delete (backspace)
    case 53: return 0xff1b  // escape
    case 55: return 0xffeb  // Left Command → Super_L
    case 56: return 0xffe1  // Left Shift
    case 57: return 0xffe5  // Caps Lock
    case 58: return 0xffe9  // Left Option → Alt_L
    case 59: return 0xffe3  // Left Control
    case 60: return 0xffe2  // Right Shift
    case 61: return 0xffea  // Right Option → Alt_R
    case 62: return 0xffe4  // Right Control
    case 96: return 0xffc2  // F5
    case 97: return 0xffc3
    case 98: return 0xffc4
    case 99: return 0xffc0
    case 100: return 0xffc5
    case 101: return 0xffc6
    case 103: return 0xffc8
    case 105: return 0xffc7
    case 109: return 0xffc9
    case 118: return 0xffc1
    case 120: return 0xffbf
    case 122: return 0xffbe
    case 123: return 0xff51
    case 124: return 0xff53
    case 125: return 0xff54
    case 126: return 0xff52
    case 117: return 0xffff
    case 115: return 0xff50
    case 119: return 0xff57
    case 116: return 0xff55
    case 121: return 0xff56
    case 114: return 0xff63  // Insert
    default:
      return nil
    }
  }
}
