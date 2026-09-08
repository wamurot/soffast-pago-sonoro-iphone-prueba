import Foundation
import Combine
import AVFoundation
import UserNotifications

@MainActor
final class SpeechNotificationManager: ObservableObject {
    @Published var status = "Preparando…"
    @Published var isWorking = false
    @Published var lastSucceeded = false
    @Published var countdownHint = false

    private var liveSynthesizer: AVSpeechSynthesizer?
    private var fileSynthesizer: AVSpeechSynthesizer?

    private let phrase = "Pago recibido de Walter, diez soles."

    func requestNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])

            status = granted
                ? "Notificaciones autorizadas. Lista para probar."
                : "Permite notificaciones para realizar la prueba."
        } catch {
            status = "No se pudo solicitar permiso: \(error.localizedDescription)"
        }
    }

    func testVoiceNow() {
        let synth = AVSpeechSynthesizer()
        liveSynthesizer = synth

        let utterance = makeUtterance(text: phrase)
        synth.speak(utterance)

        status = "Reproduciendo voz directamente…"
        lastSucceeded = true
    }

    func scheduleLockedPhoneTest() async {
        isWorking = true
        lastSucceeded = false
        countdownHint = false
        status = "Generando audio local…"

        do {
            let settings = await UNUserNotificationCenter.current().notificationSettings()

            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else {
                throw TestError.notificationsNotAllowed
            }

            let soundURL = try await generateNotificationSound(text: phrase)

            guard FileManager.default.fileExists(atPath: soundURL.path) else {
                throw TestError.soundNotCreated
            }

            let content = UNMutableNotificationContent()
            content.title = "Soffast Pago Sonoro"
            content.subtitle = "Pago recibido"
            content.body = "Walter · S/ 10.00"
            content.sound = UNNotificationSound(
                named: UNNotificationSoundName(rawValue: soundURL.lastPathComponent)
            )
            content.interruptionLevel = .timeSensitive

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: 10,
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: "soffast-\(UUID().uuidString)",
                content: content,
                trigger: trigger
            )

            try await UNUserNotificationCenter.current().add(request)

            status = "Prueba programada correctamente."
            lastSucceeded = true
            countdownHint = true
        } catch {
            status = "Error: \(error.localizedDescription)"
            lastSucceeded = false
            countdownHint = false
        }

        isWorking = false
    }

    private func makeUtterance(text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice =
            AVSpeechSynthesisVoice(language: "es-PE")
            ?? AVSpeechSynthesisVoice(language: "es-MX")
            ?? AVSpeechSynthesisVoice(language: "es-ES")
        utterance.rate = 0.47
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        return utterance
    }

    private func generateNotificationSound(text: String) async throws -> URL {
        let libraryURL = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        )[0]

        let soundsDirectory = libraryURL.appendingPathComponent(
            "Sounds",
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: soundsDirectory,
            withIntermediateDirectories: true
        )

        let destination = soundsDirectory.appendingPathComponent(
            "soffast_pago_prueba.caf"
        )

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let synth = AVSpeechSynthesizer()
            self.fileSynthesizer = synth

            let utterance = self.makeUtterance(text: text)
            var audioFile: AVAudioFile?
            var completed = false

            func finish(_ result: Result<URL, Error>) {
                guard !completed else { return }
                completed = true
                self.fileSynthesizer = nil
                continuation.resume(with: result)
            }

            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else {
                    return
                }

                if pcm.frameLength == 0 {
                    finish(.success(destination))
                    return
                }

                do {
                    if audioFile == nil {
                        audioFile = try AVAudioFile(
                            forWriting: destination,
                            settings: pcm.format.settings
                        )
                    }

                    try audioFile?.write(from: pcm)
                } catch {
                    finish(.failure(error))
                }
            }
        }
    }
}

enum TestError: LocalizedError {
    case notificationsNotAllowed
    case soundNotCreated

    var errorDescription: String? {
        switch self {
        case .notificationsNotAllowed:
            return "Las notificaciones no están autorizadas."
        case .soundNotCreated:
            return "No se pudo crear el audio de prueba."
        }
    }
}
