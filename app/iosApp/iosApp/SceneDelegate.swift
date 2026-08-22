//
//  SceneDelegate.swift
//  iosApp
//
//  Created by ByteDance on 2025/2/19.
//

import UIKit

/// App-owned navigation shell. Lynx renders its own page chrome, so UIKit's
/// navigation bar stays hidden while the native stack still owns push/pop and
/// the system's interactive leading-edge pop gesture.
private final class LynxNavigationController: UINavigationController,
    UIGestureRecognizerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        setNavigationBarHidden(true, animated: false)
        interactivePopGestureRecognizer?.delegate = self
    }

    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }

    override var childForStatusBarHidden: UIViewController? {
        topViewController
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer else {
            return true
        }
        return viewControllers.count > 1 && transitionCoordinator == nil
    }
}

/// Resolves `scheme://host/path?query` deep links against the shared
/// `contracts/deeplinks.json` config shipped inside the lynxbundle folder
/// (see scripts/sync-native.mjs). Foreign schemes return nil; our scheme
/// with an unknown host or path falls back to the configured default bundle
/// with no params. A match merges the route's static params with the URL
/// query (query values win).
private enum DeepLinkResolver {
    struct Resolution {
        let bundle: String
        let params: [String: Any]
    }

    private static let bundleNamePattern = "^[a-z0-9][a-z0-9-]*$"
    private static var cachedConfig: [String: Any]?

    static func resolve(_ url: URL) -> Resolution? {
        guard let config = loadConfig(),
              let scheme = config["scheme"] as? String,
              url.scheme?.lowercased() == scheme.lowercased() else { return nil }

        guard let route = matchedRoute(config, url) else {
            let fallback = config["defaultBundle"] as? String ?? "main"
            return isValidBundle(fallback) ? Resolution(bundle: fallback, params: [:]) : nil
        }
        guard let bundle = route["bundle"] as? String, isValidBundle(bundle) else { return nil }

        var params = route["params"] as? [String: Any] ?? [:]
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items {
                params[item.name] = item.value ?? ""
            }
        }
        return Resolution(bundle: bundle, params: params)
    }

    private static func matchedRoute(
        _ config: [String: Any],
        _ url: URL
    ) -> [String: Any]? {
        guard let host = config["host"] as? String,
              url.host?.lowercased() == host.lowercased(),
              let routes = config["routes"] as? [[String: Any]] else { return nil }
        let path = normalizedPath(url.path)
        return routes.first { $0["path"] as? String == path }
    }

    private static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "/" : "/" + trimmed
    }

    private static func isValidBundle(_ name: String) -> Bool {
        name.range(of: bundleNamePattern, options: .regularExpression) != nil
    }

    private static func loadConfig() -> [String: Any]? {
        if let cachedConfig { return cachedConfig }
        guard
            let url = Bundle.main.url(
                forResource: "deeplinks",
                withExtension: "json",
                subdirectory: "lynxbundle"
            ),
            let data = try? Data(contentsOf: url),
            let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        cachedConfig = config
        return config
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // No storyboard: create the window programmatically and mount the
        // root view controller on the provided UIWindowScene. A cold start
        // from a `lynxapp://` deep link delivers the URL here.
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = Self.makeRootNavigationController(
            for: connectionOptions.urlContexts.first?.url
        )
        self.window = window
        window.makeKeyAndVisible()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // A warm deep link pushes the resolved page on top of the existing
        // stack; back returns the user to where they were. Unmatched URLs
        // leave the app untouched instead of replacing the root page.
        guard let url = URLContexts.first?.url,
              let resolution = DeepLinkResolver.resolve(url),
              let navigation = window?.rootViewController as? UINavigationController else {
            return
        }
        navigation.pushViewController(
            LynxPageViewController(
                bundleName: resolution.bundle,
                route: Self.routeDictionary(
                    bundle: resolution.bundle,
                    params: resolution.params
                ),
                transparent: false,
                statusBarStyle: .darkContent
            ),
            animated: true
        )
    }

    /// Keeps every root entry point inside the same hidden native navigation
    /// shell so Router's default `push` contract and interactive pop agree.
    static func makeRootNavigationController(for url: URL?) -> UINavigationController {
        LynxNavigationController(rootViewController: makeRootViewController(for: url))
    }

    /// Resolves `lynxapp://<host>/<path>?<query>` via the shared deep link
    /// config into a root page whose route params mirror what Router pushes
    /// for in-app navigation; unmatched links open the default home.
    static func makeRootViewController(for url: URL?) -> UIViewController {
        guard let url,
              let resolution = DeepLinkResolver.resolve(url) else {
            return ViewController()
        }
        return LynxPageViewController(
            bundleName: resolution.bundle,
            route: routeDictionary(bundle: resolution.bundle, params: resolution.params),
            transparent: false,
            statusBarStyle: .darkContent
        )
    }

    private static func routeDictionary(
        bundle: String,
        params: [String: Any]
    ) -> [String: Any] {
        [
            "bundle": bundle,
            "presentation": "push",
            "animation": "default",
            "transparent": false,
            "statusBarStyle": "dark-content",
            "params": params,
        ]
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (or an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state the next time it runs.
    }


}
