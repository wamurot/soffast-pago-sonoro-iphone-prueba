import SwiftUI
import UIKit
import UserNotifications

final class PushProbeState: ObservableObject {
    static let shared = PushProbeState()

    @Published var status = "APNs aún no comprobado."
    @Published var token = ""

    private init() {}

    func start() {
        status = "Solicitando permiso de notificaciones..."

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error {
                    self.status = "ERROR de permiso: \(error.localizedDescription)"
                    return
                }

                guard granted else {
                    self.status = "Permiso de notificaciones denegado."
                    return
                }

                self.status = "Permiso OK. Registrando con APNs..."
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        DispatchQueue.main.async {
            PushProbeState.shared.token = token
            PushProbeState.shared.status = "APNs OK: el iPhone recibió device token."
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        DispatchQueue.main.async {
            PushProbeState.shared.token = ""
            PushProbeState.shared.status = "APNs ERROR: \(error.localizedDescription)"
        }
    }
}

@main
struct SoffastPagoPruebaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
