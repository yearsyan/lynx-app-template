import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    MMKV.initialize(rootDir: nil)
    LiquidGlassElements.register()
    LynxEnv.sharedInstance()
    return true
  }
}
