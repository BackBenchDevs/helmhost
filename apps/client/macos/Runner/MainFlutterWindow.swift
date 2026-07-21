import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    HelmFbTexturePlugin.register(
      with: flutterViewController.engine.binaryMessenger,
      registry: flutterViewController.engine
    )

    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      HelmFbTexturePlugin.register(
        with: controller.engine.binaryMessenger,
        registry: controller.engine
      )
    }

    super.awakeFromNib()
  }
}
