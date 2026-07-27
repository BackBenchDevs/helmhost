import Cocoa
import FlutterMacOS

/// CGEventTap exclusive keyboard grab → MethodChannel helmhost/exclusive_grab.
enum ExclusiveGrabBridge {
  private static var channel: FlutterMethodChannel?
  private static var tap: CFMachPort?
  private static var runLoopSource: CFRunLoopSource?
  private static var active = false
  private static var releaseArmed = false

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
    let isDown: Bool
    switch type {
    case .keyDown:
      isDown = true
    case .keyUp:
      isDown = false
    case .flagsChanged:
      // Modifier transitions — treat as down when flag present.
      let flags = event.flags
      isDown = modifierDown(keyCode: keyCode, flags: flags)
    default:
      return Unmanaged.passUnretained(event)
    }

    // Right Command alone = release (do not forward to remote).
    if keyCode == 54 {  // kVK_RightCommand
      if isDown {
        releaseArmed = true
      } else if releaseArmed {
        releaseArmed = false
        DispatchQueue.main.async {
          channel?.invokeMethod("releaseChord", arguments: nil)
        }
      }
      return nil  // swallow
    }
    if isDown {
      releaseArmed = false
    }

    if let keysym = keysym(forKeyCode: keyCode, event: event) {
      let args: [String: Any] = ["keysym": keysym, "down": isDown]
      DispatchQueue.main.async {
        channel?.invokeMethod("key", arguments: args)
      }
    }
    return nil  // swallow
  }

  private static func modifierDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
    switch keyCode {
    case 54, 55:  // Right/Left Command
      return flags.contains(.maskCommand)
    case 59, 62:  // Left/Right Control
      return flags.contains(.maskControl)
    case 56, 60:  // Left/Right Shift
      return flags.contains(.maskShift)
    case 58, 61:  // Left/Right Option
      return flags.contains(.maskAlternate)
    default:
      return false
    }
  }

  /// Map macOS virtual key code → X11 keysym (lowercase Latin-1 letters).
  private static func keysym(forKeyCode keyCode: Int64, event: CGEvent) -> Int? {
    switch keyCode {
    case 0: return 0x0061  // a
    case 1: return 0x0073  // s
    case 2: return 0x0064  // d
    case 3: return 0x0066  // f
    case 4: return 0x0068  // h
    case 5: return 0x0067  // g
    case 6: return 0x007a  // z
    case 7: return 0x0078  // x
    case 8: return 0x0063  // c
    case 9: return 0x0076  // v
    case 11: return 0x0062  // b
    case 12: return 0x0071  // q
    case 13: return 0x0077  // w
    case 14: return 0x0065  // e
    case 15: return 0x0072  // r
    case 16: return 0x0079  // y
    case 17: return 0x0074  // t
    case 18: return 0x0031  // 1
    case 19: return 0x0032
    case 20: return 0x0033
    case 21: return 0x0034
    case 22: return 0x0036
    case 23: return 0x0035
    case 24: return 0x003d  // =
    case 25: return 0x0039
    case 26: return 0x0037
    case 27: return 0x002d  // -
    case 28: return 0x0038
    case 29: return 0x0030
    case 30: return 0x005d  // ]
    case 31: return 0x006f  // o
    case 32: return 0x0075  // u
    case 33: return 0x005b  // [
    case 34: return 0x0069  // i
    case 35: return 0x0070  // p
    case 36: return 0xff0d  // return
    case 37: return 0x006c  // l
    case 38: return 0x006a  // j
    case 39: return 0x0027  // '
    case 40: return 0x006b  // k
    case 41: return 0x003b  // ;
    case 42: return 0x005c  // \
    case 43: return 0x002c  // ,
    case 44: return 0x002f  // /
    case 45: return 0x006e  // n
    case 46: return 0x006d  // m
    case 47: return 0x002e  // .
    case 48: return 0xff09  // tab
    case 49: return 0x0020  // space
    case 50: return 0x0060  // `
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
    case 63: return 0xff7e  // fn (ignore-ish)
    case 96: return 0xffc2  // F5
    case 97: return 0xffc3  // F6
    case 98: return 0xffc4  // F7
    case 99: return 0xffc0  // F3
    case 100: return 0xffc5  // F8
    case 101: return 0xffc6  // F9
    case 103: return 0xffc8  // F11
    case 105: return 0xffc7  // F10? layout varies
    case 109: return 0xffc9  // F12
    case 118: return 0xffc1  // F4
    case 120: return 0xffbf  // F2
    case 122: return 0xffbe  // F1
    case 123: return 0xff51  // left
    case 124: return 0xff53  // right
    case 125: return 0xff54  // down
    case 126: return 0xff52  // up
    case 117: return 0xffff  // forward delete
    case 115: return 0xff50  // home
    case 119: return 0xff57  // end
    case 116: return 0xff55  // page up
    case 121: return 0xff56  // page down
    default:
      return nil
    }
  }
}
