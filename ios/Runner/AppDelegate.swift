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
