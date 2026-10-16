import SwiftUI

#if os(iOS)
@MainActor
final class PushNotifications: NSObject, UIApplicationDelegate {
    static var synchronize: (() async -> Bool)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Keep the background notification open until the coordinator has saved
        // fetched state. CKSyncEngine also receives its subscription notifications.
        Task {
            let changed = await Self.synchronize?() ?? false
            completionHandler(changed ? .newData : .noData)
        }
    }
}
#else
@MainActor
final class PushNotifications: NSObject, NSApplicationDelegate {
    static var synchronize: (() async -> Bool)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task { _ = await Self.synchronize?() }
    }
}
#endif
