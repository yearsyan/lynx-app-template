import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // MMKV bootstrap lives in the autolinked NativeKVModule library.
    LiquidGlassElements.register()
    // LynxEnv init drives the LynxService lazy-load scan; it must run before
    // any LynxServices.getInstanceWith lookup or the registry is still empty.
    let lynxEnv = LynxEnv.sharedInstance()
    #if DEBUG
    // Lynx DevTool service auto-registers via @LynxServiceRegister; enabling
    // it also starts the DebugRouter TCP listener (ports 8901+) and provides
    // the LynxWebSocketModule used by the rspeedy HMR client.
    // LynxDevtool/DebugRouter pods are linked into Debug builds only.
    let devTool = LynxServices.getInstanceWith(
      LynxServiceDevToolProtocol.self
    ) as? LynxServiceDevToolProtocol
    devTool?.enableAllSessions()
    devTool?.lynxDebugPresetValue = true
    devTool?.logBoxPresetValue = true
    lynxEnv.lynxDebugEnabled = true
    lynxEnv.devtoolEnabled = true
    lynxEnv.logBoxEnabled = true
    #endif
    return true
  }
}
