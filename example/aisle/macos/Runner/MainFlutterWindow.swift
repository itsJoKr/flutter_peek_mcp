import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    // A phone-sized window, so the shop looks the way it does on a phone.
    self.setFrame(
      NSRect(x: windowFrame.minX, y: windowFrame.maxY - 860, width: 430, height: 860),
      display: true)
    self.title = "Aisle"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
