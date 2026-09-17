import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var manager = PagoTestManager()
    @StateObject private var push = PushProbeState.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 64))
                    .padding(.top, 18)

                Text("SofPago")
                    .font(.largeTitle.bold())

                Text("iPhone V5 — prueba APNs")
                    .font(.headline)

                Group {
                    Text("PASO 1: comprobar si esta instalación permite Push de Apple")
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text(push.status)
                        .font(.subheadline.bold())
                        .multilineTextAlignment(.center)

                    Button("Comprobar APNs ahora") {
                        push.start()
                    }
                    .buttonStyle(.borderedProminent)

                    if !push.token.isEmpty {
                        Text("DEVICE TOKEN")
                            .font(.caption.bold())

                        Text(push.token)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                    }

                    Text("Si aparece APNs OK y un device token, podemos pasar a la prueba real con la app forzada a cerrar. Si aparece un error de aps-environment, la firma usada por Sideloadly no tiene Push habilitado.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                Divider().padding(.vertical, 4)

                Text(manager.backgroundModeStatus)
                    .font(.subheadline.bold())
                    .multilineTextAlignment(.center)

                Text(manager.status)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Escuchar voz ahora") {
                    manager.speakNow()
                }
                .buttonStyle(.borderedProminent)

                Button("Probar bloqueado con multimedia") {
                    manager.prepareLockedMultimediaTest()
                }
                .buttonStyle(.borderedProminent)

                Button("Detener prueba") {
                    manager.stopTest()
                }
                .buttonStyle(.bordered)

                Text("La prueba de audio sigue en 5 segundos. V5 añade únicamente la comprobación real de APNs antes de construir el envío remoto con la app cerrada.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
        }
        .padding(.horizontal)
    }
}

final class PagoTestManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var status = "Prueba primero la voz. Luego prueba con el iPhone bloqueado."
    @Published var backgroundModeStatus = "Comprobando audio en segundo plano..."

    private let synthesizer = AVSpeechSynthesizer()
    private var fileGenerator: SpeechWithSilenceFileGenerator?
    private var lockedPlayer: AVAudioPlayer?

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true

        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        backgroundModeStatus = modes.contains("audio")
            ? "BACKGROUND AUDIO EN IPA: OK"
            : "BACKGROUND AUDIO EN IPA: FALTA"
    }

    func speakNow() {
        stopLockedPlayback()
        synthesizer.stopSpeaking(at: .immediate)

        do {
            try activateMultimediaSession()
            let utterance = paymentUtterance()
            synthesizer.speak(utterance)
            status = "Reproduciendo por audio multimedia: Yape, Walter, diez soles."
        } catch {
            status = "No se pudo activar el audio multimedia: \(error.localizedDescription)"
        }
    }

    func prepareLockedMultimediaTest() {
        stopLockedPlayback()
        synthesizer.stopSpeaking(at: .immediate)

        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        guard modes.contains("audio") else {
            status = "ERROR: este IPA no contiene UIBackgroundModes=audio."
            return
        }

        do {
            try activateMultimediaSession()
        } catch {
            status = "No se pudo activar el audio multimedia: \(error.localizedDescription)"
            return
        }

        status = "Generando prueba de 5 segundos..."

        let generator = SpeechWithSilenceFileGenerator()
        fileGenerator = generator

        generator.generate(
            text: "Yape, Walter, diez soles.",
            silenceSeconds: 5.0
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fileGenerator = nil

                switch result {
                case .failure(let error):
                    self.status = "No se pudo preparar el audio: \(error.localizedDescription)"
                    self.deactivateSession()

                case .success(let url):
                    do {
                        let player = try AVAudioPlayer(contentsOf: url)
                        player.delegate = self
                        player.volume = 1.0
                        player.prepareToPlay()
                        self.lockedPlayer = player

                        guard player.play() else {
                            self.status = "iOS no inició la reproducción multimedia."
                            self.lockedPlayer = nil
                            self.deactivateSession()
                            return
                        }

                        self.status = "REPRODUCCIÓN MULTIMEDIA ACTIVA. Bloquea el iPhone AHORA. En 5 segundos debe hablar."
                    } catch {
                        self.status = "No se pudo iniciar el reproductor: \(error.localizedDescription)"
                        self.deactivateSession()
                    }
                }
            }
        }
    }

    func stopTest() {
        synthesizer.stopSpeaking(at: .immediate)
        stopLockedPlayback()
        deactivateSession()
        status = "Prueba detenida."
    }

    private func activateMultimediaSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }

    private func paymentUtterance() -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: "Yape, Walter, diez soles.")
        utterance.voice = AVSpeechSynthesisVoice(language: "es-PE")
            ?? AVSpeechSynthesisVoice(language: "es-ES")
        utterance.rate = 0.48
        utterance.volume = 1.0
        return utterance
    }

    private func stopLockedPlayback() {
        lockedPlayer?.stop()
        lockedPlayer = nil
        fileGenerator = nil
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // La desactivación no debe bloquear la prueba.
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lockedPlayer = nil
            self.deactivateSession()
            self.status = flag
                ? "PRUEBA TERMINADA."
                : "La reproducción terminó de forma inesperada."
        }
    }
}

final class SpeechWithSilenceFileGenerator: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioFile: AVAudioFile?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var destination: URL?
    private var silenceWritten = false
    private var finished = false
    private var silenceSeconds: Double = 5.0

    func generate(
        text: String,
        silenceSeconds: Double,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.completion = completion
        self.silenceSeconds = silenceSeconds

        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("sofpago_multimedia_v5.caf")
            destination = url

            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "es-PE")
                ?? AVSpeechSynthesisVoice(language: "es-ES")
            utterance.rate = 0.48
            utterance.volume = 1.0

            synthesizer.write(utterance) { [weak self] buffer in
                guard let self, !self.finished else { return }

                guard let pcm = buffer as? AVAudioPCMBuffer else {
                    self.finish(.failure(PagoTestError.invalidAudioBuffer))
                    return
                }

                if pcm.frameLength == 0 {
                    self.audioFile = nil
                    guard let destination = self.destination else {
                        self.finish(.failure(PagoTestError.outputUnavailable))
                        return
                    }
                    self.finish(.success(destination))
                    return
                }

                do {
                    if self.audioFile == nil {
                        guard let destination = self.destination else {
                            throw PagoTestError.outputUnavailable
                        }

                        self.audioFile = try AVAudioFile(
                            forWriting: destination,
                            settings: pcm.format.settings
                        )
                    }

                    if !self.silenceWritten {
                        guard let file = self.audioFile else {
                            throw PagoTestError.outputUnavailable
                        }
                        try self.writeSilence(
                            seconds: self.silenceSeconds,
                            format: pcm.format,
                            to: file
                        )
                        self.silenceWritten = true
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

    private func writeSilence(
        seconds: Double,
        format: AVAudioFormat,
        to file: AVAudioFile
    ) throws {
        var remaining = AVAudioFrameCount(format.sampleRate * seconds)
        let chunkCapacity: AVAudioFrameCount = 4096

        while remaining > 0 {
            let frames = min(remaining, chunkCapacity)

            guard let silence = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frames
            ) else {
                throw PagoTestError.invalidAudioBuffer
            }

            silence.frameLength = frames

            let buffers = UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList)
            for buffer in buffers {
                if let data = buffer.mData, buffer.mDataByteSize > 0 {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }

            try file.write(from: silence)
            remaining -= frames
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !finished else { return }
        finished = true
        let callback = completion
        completion = nil
        callback?(result)
    }
}

enum PagoTestError: LocalizedError {
    case invalidAudioBuffer
    case outputUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidAudioBuffer:
            return "El sintetizador devolvió un formato de audio inesperado."
        case .outputUnavailable:
            return "No se pudo preparar el archivo de audio."
        }
    }
}
