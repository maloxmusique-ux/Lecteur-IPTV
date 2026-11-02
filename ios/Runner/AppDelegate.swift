import AVFoundation
import AVKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CanalixAirPlay") {
      let channel = FlutterMethodChannel(name: "canalix/airplay", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "play", let args = call.arguments as? [String: Any],
              let s = args["url"] as? String, let url = URL(string: s) else {
          result(FlutterMethodNotImplemented)
          return
        }
        AirPlayPresenter.present(url: url, title: args["title"] as? String ?? "",
                                 userAgent: args["userAgent"] as? String ?? "")
        result(nil)
      }
    }
    // Mini-lecteur : la video passe directement dans une fenetre flottante
    // (sans ouvrir l'ecran du lecteur Apple).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CanalixPip") {
      let channel = FlutterMethodChannel(name: "canalix/pip", binaryMessenger: registrar.messenger())
      MiniPlayer.shared.channel = channel
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "supported":
          result(AVPictureInPictureController.isPictureInPictureSupported())
        case "start":
          guard let args = call.arguments as? [String: Any],
                let s = args["url"] as? String, let url = URL(string: s) else {
            result(false)
            return
          }
          MiniPlayer.shared.start(url: url, userAgent: args["userAgent"] as? String ?? "",
                                  startAt: args["position"] as? Double ?? 0, result: result)
        case "stop":
          MiniPlayer.shared.stop()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

/// Fenetre flottante (image dans l'image) d'iOS. Elle exige le lecteur
/// Apple : on le prepare cache, et des que l'image est prete, la video
/// s'envole dans la petite fenetre.
final class MiniPlayer: NSObject, AVPictureInPictureControllerDelegate {
  static let shared = MiniPlayer()
  var channel: FlutterMethodChannel?

  private var player: AVPlayer?
  private var layerView: UIView?
  private var pip: AVPictureInPictureController?
  private var observations: [NSKeyValueObservation] = []
  private var pending: FlutterResult?
  private var timeout: DispatchWorkItem?
  private var restoring = false

  func start(url: URL, userAgent: String, startAt: Double, result: @escaping FlutterResult) {
    stop()
    guard AVPictureInPictureController.isPictureInPictureSupported(),
          let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else {
      result(false)
      return
    }
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    try? AVAudioSession.sharedInstance().setActive(true)

    var options: [String: Any] = [:]
    if !userAgent.isEmpty { options["AVURLAssetHTTPHeaderFieldsKey"] = ["User-Agent": userAgent] }
    let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
    let player = AVPlayer(playerItem: item)
    player.allowsExternalPlayback = true

    // Couche video dans la fenetre, sous l'interface de l'app (invisible).
    let view = UIView(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
    view.isUserInteractionEnabled = false
    view.alpha = 0.011
    let layer = AVPlayerLayer(player: player)
    layer.frame = view.bounds
    layer.videoGravity = .resizeAspect
    view.layer.addSublayer(layer)
    window.addSubview(view)
    window.sendSubviewToBack(view)

    guard let pip = AVPictureInPictureController(playerLayer: layer) else {
      view.removeFromSuperview()
      result(false)
      return
    }
    pip.delegate = self
    if #available(iOS 14.2, *) { pip.canStartPictureInPictureAutomaticallyFromInline = true }
    self.player = player
    self.layerView = view
    self.pip = pip
    self.pending = result

    if startAt > 1 {
      player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
    }
    player.play()

    // Des que la fenetre flottante est possible et l'image prete : on lance.
    let tryStart: () -> Void = { [weak self] in
      guard let self, let pip = self.pip, self.pending != nil else { return }
      if pip.isPictureInPicturePossible && item.status == .readyToPlay && layer.isReadyForDisplay {
        pip.startPictureInPicture()
      }
    }
    observations = [
      pip.observe(\.isPictureInPicturePossible, options: [.new]) { _, _ in DispatchQueue.main.async(execute: tryStart) },
      item.observe(\.status, options: [.new]) { [weak self] it, _ in
        DispatchQueue.main.async {
          if it.status == .failed { self?.finish(false); self?.stop() } else { tryStart() }
        }
      },
      layer.observe(\.isReadyForDisplay, options: [.new]) { _, _ in DispatchQueue.main.async(execute: tryStart) },
    ]
    let t = DispatchWorkItem { [weak self] in
      guard let self, self.pending != nil else { return }
      self.finish(false)
      self.stop()
    }
    timeout = t
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: t)
  }

  private func finish(_ ok: Bool) {
    timeout?.cancel()
    pending?(ok)
    pending = nil
  }

  func stop() {
    timeout?.cancel()
    observations.forEach { $0.invalidate() }
    observations = []
    if pip?.isPictureInPictureActive == true { pip?.stopPictureInPicture() }
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    layerView?.removeFromSuperview()
    pip = nil
    player = nil
    layerView = nil
  }

  // MARK: AVPictureInPictureControllerDelegate

  func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
    finish(true)
  }

  func pictureInPictureController(_ c: AVPictureInPictureController,
                                  failedToStartPictureInPictureWithError error: Error) {
    finish(false)
    stop()
  }

  // Bouton « revenir dans l'app » de la fenetre flottante.
  func pictureInPictureController(_ c: AVPictureInPictureController,
      restoreUserInterfaceForPictureInPictureStopWithCompletionHandler done: @escaping (Bool) -> Void) {
    restoring = true
    let pos = player?.currentTime().seconds ?? 0
    channel?.invokeMethod("restore", arguments: ["position": pos.isFinite ? pos : 0])
    done(true)
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
    let restored = restoring
    restoring = false
    if !restored { channel?.invokeMethod("closed", arguments: nil) }
    DispatchQueue.main.async { self.stop() }
  }
}

/// Lecteur Apple (AVPlayer) avec le bouton AirPlay : la tele (Apple TV,
/// Samsung, LG...) lit directement le flux.
enum AirPlayPresenter {
  static func present(url: URL, title: String, userAgent: String) {
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    try? AVAudioSession.sharedInstance().setActive(true)
    var options: [String: Any] = [:]
    if !userAgent.isEmpty {
      options["AVURLAssetHTTPHeaderFieldsKey"] = ["User-Agent": userAgent]
    }
    let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
    let player = AVPlayer(playerItem: item)
    player.allowsExternalPlayback = true
    player.usesExternalPlaybackWhileExternalScreenIsActive = true
    let vc = AVPlayerViewController()
    vc.player = player
    vc.title = title
    vc.modalPresentationStyle = .fullScreen
    // Mini-lecteur : bouton PiP, et demarrage automatique en quittant l'app.
    vc.allowsPictureInPicturePlayback = true
    vc.canStartPictureInPictureAutomaticallyFromInline = true
    vc.updatesNowPlayingInfoCenter = true

    // Bouton AirPlay bien visible en haut.
    let picker = AVRoutePickerView()
    picker.prioritizesVideoDevices = true
    picker.tintColor = .white
    picker.activeTintColor = .systemBlue
    picker.translatesAutoresizingMaskIntoConstraints = false
    vc.contentOverlayView?.addSubview(picker)

    guard let root = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
    var top = root
    while let p = top.presentedViewController { top = p }
    top.present(vc, animated: true) {
      if let overlay = vc.contentOverlayView {
        NSLayoutConstraint.activate([
          picker.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -16),
          picker.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -90),
          picker.widthAnchor.constraint(equalToConstant: 44),
          picker.heightAnchor.constraint(equalToConstant: 44),
        ])
      }
      player.play()
    }
  }
}
