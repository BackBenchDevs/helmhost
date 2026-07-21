import Accelerate
import Cocoa
import CoreVideo
import FlutterMacOS

/// RGBA8 pixel buffer texture for VNC framebuffer presentation.
final class HelmFbTexture: NSObject, FlutterTexture {
  private var pixelBuffer: CVPixelBuffer?
  private let lock = NSLock()
  private(set) var width: Int = 0
  private(set) var height: Int = 0

  func ensureSize(width: Int, height: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if pixelBuffer != nil, self.width == width, self.height == height {
      return true
    }
    self.width = width
    self.height = height
    pixelBuffer = nil
    var pb: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &pb
    )
    guard status == kCVReturnSuccess, let created = pb else {
      return false
    }
    pixelBuffer = created
    return true
  }

  /// Copy RGBA source into BGRA CVPixelBuffer (Accelerate).
  func copyRGBA(_ src: UnsafePointer<UInt8>, width: Int, height: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let pb = pixelBuffer, self.width == width, self.height == height else {
      return false
    }
    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }
    guard let dst = CVPixelBufferGetBaseAddress(pb) else { return false }
    let dstStride = CVPixelBufferGetBytesPerRow(pb)
    var srcBuf = vImage_Buffer(
      data: UnsafeMutableRawPointer(mutating: src),
      height: vImagePixelCount(height),
      width: vImagePixelCount(width),
      rowBytes: width * 4
    )
    var dstBuf = vImage_Buffer(
      data: dst,
      height: vImagePixelCount(height),
      width: vImagePixelCount(width),
      rowBytes: dstStride
    )
    // RGBA8888 → BGRA8888 permute
    let map: [UInt8] = [2, 1, 0, 3]
    let err = vImagePermuteChannels_ARGB8888(&srcBuf, &dstBuf, map, vImage_Flags(kvImageNoFlags))
    return err == kvImageNoError
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard let pb = pixelBuffer else { return nil }
    return Unmanaged.passRetained(pb)
  }
}

/// Method channel + FFI present path (no Dart pixel transfer).
enum HelmFbTexturePlugin {
  private static var textures: [Int64: HelmFbTexture] = [:]
  private static var registry: FlutterTextureRegistry?
  private static var ffiLoaded = false
  private static var hhFbSize: (@convention(c) (UInt64, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> Int32)?
  private static var hhFbCopy: (@convention(c) (UInt64, UnsafeMutablePointer<UInt8>, Int) -> Int32)?

  static func register(with messenger: FlutterBinaryMessenger, registry: FlutterTextureRegistry) {
    self.registry = registry
    loadFfi()
    let channel = FlutterMethodChannel(name: "helmhost/fb_texture", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "create":
        guard let registry = self.registry else {
          result(FlutterError(code: "no_registry", message: nil, details: nil))
          return
        }
        let tex = HelmFbTexture()
        let tid = registry.register(tex)
        textures[tid] = tex
        result(NSNumber(value: tid))
      case "present":
        guard
          let args = call.arguments as? [String: Any],
          let textureId = (args["textureId"] as? NSNumber)?.int64Value,
          let sessionId = (args["sessionId"] as? NSNumber)?.uint64Value,
          let tex = textures[textureId],
          let registry = self.registry
        else {
          result(FlutterError(code: "bad_args", message: nil, details: nil))
          return
        }
        switch present(sessionId: sessionId, texture: tex) {
        case .ok:
          registry.textureFrameAvailable(textureId)
          result("ok")
        case .skipped:
          // No framebuffer yet — normal right after connect.
          result("skipped")
        case .noFfi:
          result(FlutterError(code: "no_ffi", message: "libhelmhost_ffi.dylib not loaded", details: nil))
        case .failed:
          result(FlutterError(code: "present_failed", message: nil, details: nil))
        }
      case "dispose":
        guard
          let args = call.arguments as? [String: Any],
          let textureId = (args["textureId"] as? NSNumber)?.int64Value
        else {
          result(nil)
          return
        }
        textures.removeValue(forKey: textureId)
        Self.registry?.unregisterTexture(textureId)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func loadFfi() {
    guard !ffiLoaded else { return }
    ffiLoaded = true
    let name = "libhelmhost_ffi.dylib"
    let bundle = Bundle.main
    let macosDir = bundle.bundleURL
      .appendingPathComponent("Contents/MacOS", isDirectory: true)
      .appendingPathComponent(name)
    let nextToExe = bundle.executableURL?
      .deletingLastPathComponent()
      .appendingPathComponent(name)
    let candidates: [URL?] = [
      macosDir,
      nextToExe,
      bundle.privateFrameworksURL?.appendingPathComponent(name),
      bundle.bundleURL.appendingPathComponent("Contents/Frameworks/\(name)"),
      bundle.resourceURL?.appendingPathComponent(name),
      URL(fileURLWithPath: name),
    ]
    var handle: UnsafeMutableRawPointer?
    var loadedPath: String?
    for url in candidates {
      guard let path = url?.path else { continue }
      handle = dlopen(path, RTLD_NOW)
      if handle != nil {
        loadedPath = path
        break
      }
    }
    guard let handle else {
      NSLog("helmhost: dlopen(\(name)) failed — tried Contents/MacOS and Frameworks")
      return
    }
    NSLog("helmhost: loaded FFI from \(loadedPath ?? "?")")
    typealias SizeFn = @convention(c) (UInt64, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> Int32
    typealias CopyFn = @convention(c) (UInt64, UnsafeMutablePointer<UInt8>, Int) -> Int32
    if let sym = dlsym(handle, "hh_fb_size") {
      hhFbSize = unsafeBitCast(sym, to: SizeFn.self)
    }
    if let sym = dlsym(handle, "hh_fb_copy") {
      hhFbCopy = unsafeBitCast(sym, to: CopyFn.self)
    }
    if hhFbSize == nil || hhFbCopy == nil {
      NSLog("helmhost: hh_fb_size/hh_fb_copy symbols missing")
    }
  }

  private enum PresentResult {
    case ok
    case skipped
    case noFfi
    case failed
  }

  private static func present(sessionId: UInt64, texture: HelmFbTexture) -> PresentResult {
    guard let sizeFn = hhFbSize, let copyFn = hhFbCopy else { return .noFfi }
    var w: UInt32 = 0
    var h: UInt32 = 0
    if sizeFn(sessionId, &w, &h) != 0 { return .failed }
    if w == 0 || h == 0 { return .skipped }
    let wi = Int(w)
    let hi = Int(h)
    if !texture.ensureSize(width: wi, height: hi) { return .failed }
    let len = wi * hi * 4
    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: len)
    defer { buf.deallocate() }
    if copyFn(sessionId, buf, len) != 0 { return .failed }
    return texture.copyRGBA(buf, width: wi, height: hi) ? .ok : .failed
  }
}
