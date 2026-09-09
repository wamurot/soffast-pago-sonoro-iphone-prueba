import SwiftUI
import AVFoundation
import UserNotifications

struct ContentView: View {
    @StateObject private var manager = PagoTestManager()

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 72))

            Text("Soffast Pago")
                .font(.largeTitle.bold())

            Text("Prueba única iPhone")
                .font(.headline)

            Text(manager.status)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Escuchar voz ahora") {
                manager.speakNow()
            }
            .buttonStyle(.borderedProminent)

            Button("Probar con iPhone bloqueado") {
                manager.prepareLockedTest()
            }
            .buttonStyle(.borderedProminent)

            Text("Al pulsar la segunda opción tendrás 12 segundos para bloquear el iPhone.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}

final class PagoTestManager: ObservableObject {
    @Published var status = "Primero prueba la voz. Luego prueba con el iPhone bloqueado."

    private let liveSynth = AVSpeechSynthesizer()
    private var fileGenerator: SpeechFileGenerator?

    func speakNow() {
        let utterance = AVSpeechUtterance(string: "Yape, Walter, diez soles.")
        utterance.voice = AVSpeechSynthesisVoice(language: "es-PE")
            ?? AVSpeechSynthesisVoice(language: "es-ES")
        utterance.rate = 0.48
        liveSynth.speak(utterance)
        status = "Reproduciendo: Yape, Walter, diez soles."
    }

    func prepareLockedTest() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    self.status = "Error de permisos: \(error.localizedDescription)"
                    return
                }

                guard granted else {
                    self.status = "Debes permitir notificaciones para hacer la prueba."
                    return
                }

                self.status = "Generando audio..."
                self.generateAndSchedule()
            }
        }
    }

    private func generateAndSchedule() {
        let generator = SpeechFileGenerator()
        self.fileGenerator = generator

        generator.generate(text: "Yape, Walter, diez soles.") { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                switch result {
                case .failure(let error):
                    self.status = "No se pudo generar el audio: \(error.localizedDescription)"
                    self.fileGenerator = nil

                case .success(let filename):
                    let content = UNMutableNotificationContent()
                    content.title = "Pago"
                    content.body = "Yape, Walter, diez soles."
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(filename))

                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 12, repeats: false)
                    let request = UNNotificationRequest(
                        identifier: "soffast-pago-prueba-bloqueado",
                        content: content,
                        trigger: trigger
                    )

                    UNUserNotificationCenter.current().add(request) { error in
                        DispatchQueue.main.async {
                            if let error {
                                self.status = "No se pudo programar la prueba: \(error.localizedDescription)"
                            } else {
                                self.status = "LISTO: bloquea el iPhone ahora. Sonará en 12 segundos."
                            }
                            self.fileGenerator = nil
                        }
                    }
                }
            }
        }
    }
}

final class SpeechFileGenerator: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioFile: AVAudioFile?
    private var completed = false
    private var completion: ((Result<String, Error>) -> Void)?

    func generate(text: String, completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion

        do {
            let soundsURL = try ensureSoundsDirectory()
            let filename = "soffast_pago_prueba.caf"
            let destination = soundsURL.appendingPathComponent(filename)

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "es-PE")
                ?? AVSpeechSynthesisVoice(language: "es-ES")
            utterance.rate = 0.48

            synthesizer.write(utterance) { [weak self] buffer in
                guard let self else { return }

                guard let pcm = buffer as? AVAudioPCMBuffer else {
                    self.finish(.failure(PagoTestError.invalidAudioBuffer))
                    return
                }

                if pcm.frameLength == 0 {
                    self.audioFile = nil
                    self.finish(.success(filename))
                    return
                }

                do {
                    if self.audioFile == nil {
                        self.audioFile = try AVAudioFile(
                            forWriting: destination,
                            settings: pcm.format.settings
                        )
                    }
                    try self.audioFile?.write(from: pcm)
                } catch {
                    self.finish(.failure(error))
                }
            }
        } catch {
            finish(.failure(error))
        }
    }

    private func ensureSoundsDirectory() throws -> URL {
        guard let library = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else {
            throw PagoTestError.libraryUnavailable
        }

        let sounds = library.appendingPathComponent("Sounds", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sounds,
            withIntermediateDirectories: true
        )
        return sounds
    }

    private func finish(_ result: Result<String, Error>) {
        guard !completed else { return }
        completed = true
        let callback = completion
        completion = nil
        callback?(result)
    }
}

enum PagoTestError: LocalizedError {
    case libraryUnavailable
    case invalidAudioBuffer

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            return "No se encontró Library."
        case .invalidAudioBuffer:
            return "El sintetizador devolvió un formato de audio inesperado."
        }
    }
}
