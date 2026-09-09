import Foundation

enum DeviceRegistrationService {
    static let endpoint = URL(string: "https://voz.soffast.com/api/ios/register")!

    static func register(deviceToken: String) async {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = ["device_token": deviceToken, "platform": "ios", "app": "soffast-pago"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do { _ = try await URLSession.shared.data(for: request) }
        catch { UserDefaults.standard.set(error.localizedDescription, forKey: "soffastRegisterError") }
        await MainActor.run { NotificationCenter.default.post(name: .soffastPushStatusChanged, object: nil) }
    }
}
