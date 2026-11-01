import AVFoundation
import AVKit
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "canalix/airplay", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "play", let args = call.arguments as? [String: Any],
            let s = args["url"] as? String, let url = URL(string: s) else {
        result(FlutterMethodNotImplemented)
        return
      }
      AirPlayWindow.show(url: url, title: args["title"] as? String ?? "Canalix",
                         userAgent: args["userAgent"] as? String ?? "")
      result(nil)
    }

    super.awakeFromNib()
  }
}

/// Fenetre du lecteur Apple avec le bouton AirPlay (Apple TV, Samsung, LG...).
final class AirPlayWindow: NSObject, NSWindowDelegate {
  private static var current: AirPlayWindow?
  private let window: NSWindow
  private let player: AVPlayer

  static func show(url: URL, title: String, userAgent: String) {
    current?.window.close()
    current = AirPlayWindow(url: url, title: title, userAgent: userAgent)
  }

  private init(url: URL, title: String, userAgent: String) {
    var options: [String: Any] = [:]
    if !userAgent.isEmpty {
      options["AVURLAssetHTTPHeaderFieldsKey"] = ["User-Agent": userAgent]
    }
    player = AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: url, options: options)))
    player.allowsExternalPlayback = true

    let view = AVPlayerView()
    view.player = player
    view.controlsStyle = .floating
    view.showsFullScreenToggleButton = true

    // Bouton AirPlay en haut a droite.
    let picker = AVRoutePickerView()
    picker.translatesAutoresizingMaskIntoConstraints = false
    picker.isRoutePickerButtonBordered = false
    view.addSubview(picker)
    NSLayoutConstraint.activate([
      picker.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
      picker.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
      picker.widthAnchor.constraint(equalToConstant: 36),
      picker.heightAnchor.constraint(equalToConstant: 36),
    ])

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered, defer: false)
    super.init()
    window.title = "\(title) · AirPlay"
    window.contentView = view
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.center()
    window.makeKeyAndOrderFront(nil)
    player.play()
  }

  func windowWillClose(_ notification: Notification) {
    player.pause()
    player.replaceCurrentItem(with: nil)
    if AirPlayWindow.current === self { AirPlayWindow.current = nil }
  }
}
