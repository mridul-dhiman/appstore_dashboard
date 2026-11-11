import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The app draws its own title bar: content runs under it and the traffic-light buttons float over the top left.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    // An empty unified toolbar gives the standard tall title bar, which centres the traffic lights vertically.
    let toolbar = NSToolbar(identifier: "main")
    self.toolbar = toolbar
    self.toolbarStyle = .unified
    self.titlebarSeparatorStyle = .none
    self.minSize = NSSize(width: 980, height: 640)
    // AppKit saves and restores the window's size and position under this name between launches.
    self.setFrameAutosaveName("MainWindow")

    let channel = FlutterMethodChannel(name: "appstore_dashboard/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startDrag":
        if let event = NSApp.currentEvent { self?.performDrag(with: event) }
        result(nil)
      case "zoom":
        self?.performZoom(nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
