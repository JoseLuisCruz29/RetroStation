import AVFoundation
import Accelerate
import CoreVideo
import Flutter
import GameController
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var video: NativeVideo?
  private var sounds: UiSounds?
  private var gamepads: GamepadBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Sonido de los juegos aunque el interruptor de silencio esté activado,
    // sin cortar la música de otras apps.
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RetroStationNative") {
      video = NativeVideo(registrar: registrar)
      sounds = UiSounds(messenger: registrar.messenger())
      gamepads = GamepadBridge(messenger: registrar.messenger())
    }
  }
}

/// Imagen del emulador: el motor (retrostation_native.framework) avisa de cada
/// fotograma y Flutter lo copia como textura. Canal "retrostation/video",
/// igual que en Android y Windows ("create" devuelve el id de la textura).
final class NativeVideo: NSObject, FlutterTexture {
  private typealias CopyFn = @convention(c) (
    UnsafeMutablePointer<UInt8>?, Int32, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?
  ) -> Int32
  private typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?) -> Void
  private typealias SetCallbackFn = @convention(c) (FrameCallback?, UnsafeMutableRawPointer?) -> Void

  private let textures: FlutterTextureRegistry
  private let channel: FlutterMethodChannel
  private var copyFrame: CopyFn?
  private var setFrameCallback: SetCallbackFn?
  private var textureId: Int64 = -1
  private var rgba = [UInt8]()
  private var pool: CVPixelBufferPool?
  private var poolWidth = 0
  private var poolHeight = 0
  private var framePending = false
  private let lock = NSLock()

  init(registrar: FlutterPluginRegistrar) {
    textures = registrar.textures()
    channel = FlutterMethodChannel(name: "retrostation/video", binaryMessenger: registrar.messenger())
    super.init()
    if let dir = Bundle.main.privateFrameworksPath,
       let lib = dlopen(dir + "/retrostation_native.framework/retrostation_native", RTLD_NOW) {
      if let p = dlsym(lib, "rs_copy_frame") { copyFrame = unsafeBitCast(p, to: CopyFn.self) }
      if let p = dlsym(lib, "rs_set_frame_callback") { setFrameCallback = unsafeBitCast(p, to: SetCallbackFn.self) }
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "create": result(self.create())
      case "release":
        self.release()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func create() -> Int64 {
    release()
    textureId = textures.register(self)
    let callback: FrameCallback = { user in
      guard let user = user else { return }
      Unmanaged<NativeVideo>.fromOpaque(user).takeUnretainedValue().frameReady()
    }
    setFrameCallback?(callback, Unmanaged.passUnretained(self).toOpaque())
    return textureId
  }

  private func release() {
    setFrameCallback?(nil, nil)
    if textureId >= 0 { textures.unregisterTexture(textureId) }
    textureId = -1
  }

  /// Hilo de emulación: nuevo fotograma. Se avisa a Flutter una vez por
  /// fotograma que vaya a dibujar (los intermedios se descartan).
  private func frameReady() {
    lock.lock()
    let wasPending = framePending
    framePending = true
    lock.unlock()
    if wasPending { return }
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.textureId >= 0 else { return }
      self.textures.textureFrameAvailable(self.textureId)
    }
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    framePending = false
    lock.unlock()
    guard let copyFrame = copyFrame else { return nil }
    var width: Int32 = 0
    var height: Int32 = 0
    let needed = copyFrame(nil, 0, &width, &height)
    guard needed > 0, width > 0, height > 0 else { return nil }
    if rgba.count < Int(needed) { rgba = [UInt8](repeating: 0, count: Int(needed)) }
    let ok = rgba.withUnsafeMutableBufferPointer { copyFrame($0.baseAddress, needed, &width, &height) }
    guard ok == 0 else { return nil }

    let w = Int(width)
    let h = Int(height)
    if pool == nil || poolWidth != w || poolHeight != h {
      let attrs: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: w,
        kCVPixelBufferHeightKey as String: h,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        kCVPixelBufferMetalCompatibilityKey as String: true,
      ]
      pool = nil
      CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
      poolWidth = w
      poolHeight = h
    }
    var buffer: CVPixelBuffer?
    guard let pool = pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
          let pixels = buffer else { return nil }
    CVPixelBufferLockBaseAddress(pixels, [])
    defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
    guard let dst = CVPixelBufferGetBaseAddress(pixels) else { return nil }
    let dstRowBytes = CVPixelBufferGetBytesPerRow(pixels)
    // El motor da RGBA; la textura de iOS es BGRA.
    rgba.withUnsafeMutableBytes { src in
      var from = vImage_Buffer(data: src.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w),
                               rowBytes: w * 4)
      var to = vImage_Buffer(data: dst, height: vImagePixelCount(h), width: vImagePixelCount(w),
                             rowBytes: dstRowBytes)
      let map: [UInt8] = [2, 1, 0, 3]
      _ = vImagePermuteChannels_ARGB8888(&from, &to, map, vImage_Flags(kvImageNoFlags))
    }
    return Unmanaged.passRetained(pixels)
  }
}

/// Efectos de sonido de la interfaz (canal "retrostation/sfx", como en Android).
/// Los WAV van en Runner.app/sfx (los copia el script de compilación).
final class UiSounds {
  private let channel: FlutterMethodChannel
  private var players: [String: AVAudioPlayer] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "retrostation/sfx", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      defer { result(nil) }
      guard call.method == "play", let self = self,
            let args = call.arguments as? [String: Any], let name = args["name"] as? String else { return }
      let volume = Float((args["volume"] as? Double) ?? 1.0)
      self.play(name, volume: volume)
    }
  }

  private func play(_ name: String, volume: Float) {
    if players[name] == nil,
       let path = Bundle.main.path(forResource: "sfx_\(name)", ofType: "wav", inDirectory: "sfx") {
      players[name] = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      players[name]?.prepareToPlay()
    }
    guard let player = players[name] else { return }
    player.volume = volume
    player.currentTime = 0
    player.play()
  }
}

/// Mandos en iPhone (Pro Controller de Switch, Xbox, PlayStation, MFi...) con
/// GameController. Envía el estado a Dart por "retrostation/gamepad" en el
/// mismo formato que el PC (windows/runner/gamepad_input.cpp), con los botones
/// por posición en el orden del Pro Controller: abajo, derecha, izquierda,
/// arriba, L, R, ZL, ZR, −, +, L3, R3, Home. Así cualquier mando usa la misma
/// distribución que en la consola (lib/controllers/gamepad.dart).
final class GamepadBridge {
  private let channel: FlutterMethodChannel
  private var ids: [ObjectIdentifier: Int] = [:]
  private var nextId = 0

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "retrostation/gamepad", binaryMessenger: messenger)
    let center = NotificationCenter.default
    center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
      if let pad = note.object as? GCController { self?.attach(pad) }
    }
    center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
      guard let self = self, let pad = note.object as? GCController,
            let id = self.ids.removeValue(forKey: ObjectIdentifier(pad)) else { return }
      self.channel.invokeMethod("state", arguments: ["id": id, "connected": false])
    }
    GCController.shouldMonitorBackgroundEvents = true
    GCController.controllers().forEach(attach)
  }

  private func attach(_ pad: GCController) {
    guard let gamepad = pad.extendedGamepad else { return }
    let key = ObjectIdentifier(pad)
    if ids[key] == nil {
      ids[key] = nextId
      nextId += 1
    }
    gamepad.valueChangedHandler = { [weak self, weak pad] _, _ in
      guard let self = self, let pad = pad else { return }
      self.send(pad)
    }
    send(pad)
  }

  private func send(_ pad: GCController) {
    guard let g = pad.extendedGamepad, let id = ids[ObjectIdentifier(pad)] else { return }
    let buttons: [GCControllerButtonInput?] = [
      g.buttonA, g.buttonB, g.buttonX, g.buttonY,
      g.leftShoulder, g.rightShoulder, g.leftTrigger, g.rightTrigger,
      g.buttonOptions, g.buttonMenu, g.leftThumbstickButton, g.rightThumbstickButton, g.buttonHome,
    ]
    var mask = 0
    for (i, button) in buttons.enumerated() where button?.isPressed == true {
      mask |= 1 << i
    }
    let up = g.dpad.up.isPressed, down = g.dpad.down.isPressed
    let left = g.dpad.left.isPressed, right = g.dpad.right.isPressed
    var pov = -1
    switch (up, down, left, right) {
    case (true, _, _, true): pov = 4500
    case (_, true, _, true): pov = 13500
    case (_, true, true, _): pov = 22500
    case (true, _, true, _): pov = 31500
    case (true, _, _, _): pov = 0
    case (_, _, _, true): pov = 9000
    case (_, true, _, _): pov = 18000
    case (_, _, true, _): pov = 27000
    default: pov = -1
    }
    let stick = g.leftThumbstick
    let rstick = g.rightThumbstick
    channel.invokeMethod("state", arguments: [
      "id": id,
      "connected": true,
      "name": pad.vendorName ?? "Mando",
      // Distribución por posición (la del Pro Controller): ver la cabecera.
      "vid": 0x057e,
      "pid": 0,
      "buttons": mask,
      "pov": pov,
      // GameController: arriba es positivo; en libretro, abajo.
      "axes": [Double(stick.xAxis.value), Double(-stick.yAxis.value), 0.0,
               Double(rstick.xAxis.value), Double(-rstick.yAxis.value), 0.0],
    ])
  }
}
