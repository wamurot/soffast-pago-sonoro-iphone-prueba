import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var task: URLSessionDownloadTask?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        self.bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let content = bestAttemptContent,
              let audioURLString = request.content.userInfo["audio_url"] as? String,
              let audioURL = URL(string: audioURLString) else {
            contentHandler(request.content)
            return
        }

        let requested = (request.content.userInfo["audio_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = safeFileName((requested?.isEmpty == false ? requested! : "pago_\(request.identifier).wav"))

        task = URLSession.shared.downloadTask(with: audioURL) { [weak self] tempURL, _, error in
            guard let self else { return }
            guard error == nil, let tempURL, let destination = self.soundDestination(fileName: fileName) else {
                content.sound = .default
                contentHandler(content)
                return
            }
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.copyItem(at: tempURL, to: destination)
                content.sound = UNNotificationSound(named: UNNotificationSoundName(fileName))
            } catch { content.sound = .default }
            contentHandler(content)
        }
        task?.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        task?.cancel()
        if let contentHandler, let bestAttemptContent {
            bestAttemptContent.sound = .default
            contentHandler(bestAttemptContent)
        }
    }

    private func soundDestination(fileName: String) -> URL? {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.soffast.pago") else { return nil }
        return group.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Sounds", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let chars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(chars)
        return result.isEmpty ? "pago.wav" : String(result.prefix(90))
    }
}
