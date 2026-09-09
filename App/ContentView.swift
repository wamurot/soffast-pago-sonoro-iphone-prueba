import SwiftUI
import UIKit
import UserNotifications

struct ContentView: View {
    @State private var status = "Pulsa Activar pagos."
    @State private var busy = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "waveform.circle.fill").font(.system(size: 82))
            Text("Pago").font(.largeTitle.bold())
            Text("Avisos hablados de pagos").font(.headline)
            Text(status).multilineTextAlignment(.center).padding(.horizontal)
            Button { activate() } label: {
                Text(busy ? "Activando..." : "Activar pagos")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy)
            .padding(.horizontal, 28)
            Spacer()
        }
        .onAppear { refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .soffastPushStatusChanged)) { _ in refreshStatus() }
    }

    private func activate() {
        busy = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if let error { status = "Error: \(error.localizedDescription)"; busy = false; return }
                guard granted else { status = "Debes permitir las notificaciones."; busy = false; return }
                status = "Permiso concedido. Registrando iPhone..."
                UIApplication.shared.registerForRemoteNotifications()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { refreshStatus(); busy = false }
            }
        }
    }

    private func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let token = UserDefaults.standard.string(forKey: "soffastDeviceToken")
            let error = UserDefaults.standard.string(forKey: "soffastPushError")
            DispatchQueue.main.async {
                if let error, !error.isEmpty { status = "Push: \(error)" }
                else if settings.authorizationStatus == .authorized, token != nil { status = "Listo. Este iPhone ya puede recibir pagos." }
                else if settings.authorizationStatus == .denied { status = "Notificaciones desactivadas en Ajustes." }
                else { status = "Pulsa Activar pagos." }
            }
        }
    }
}
