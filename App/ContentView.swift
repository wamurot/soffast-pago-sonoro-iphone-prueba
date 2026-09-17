import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var manager = PagoTestManager()

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 72))

            Text("SofPago")
                .font(.largeTitle.bold())

            Text("Audio multimedia iPhone V3")
                .font(.headline)

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

            Text("En V3 la segunda prueba genera un único archivo de audio con 12 segundos iniciales de silencio y luego la frase. El archivo comienza a reproducirse antes de bloquear el iPhone, de modo que iOS mantiene una reproducción multimedia real mientras la pantalla está apagada.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}

final class PagoTestManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var status = "Prueba primero la voz. Luego prueba con el iPhone bloqueado."

    private let synthesizer = AVSpeechSynthesizer()
    private var fileGenerator: SpeechWithSilenceFileGenerator?
    private var lockedPlayer: AVAudioPlayer?

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
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

        do {
            try activateMultimediaSession()
        } catch {
            status = "No se pudo activar el audio multimedia: \(error.localizedDescription)"
            return
        }

        status = "Generando la prueba V3... espera un momento."

        let generator = SpeechWithSilenceFileGenerator()
        fileGenerator = generator

        generator.generate(
            text: "Yape, Walter, diez soles.",
            silenceSeconds: 12.0
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fileGenerator = nil

                switch result {
                case .failure(let error):
                    self.status = "No se pudo preparar el audio V3: \(error.localizedDescription)"
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

                        self.status = "SONANDO EN MULTIMEDIA. Bloquea el iPhone AHORA. En 12 segundos debe decir: Yape, Walter, diez soles."
                    } catch {
                        self.status = "No se pudo iniciar el reproductor V3: \(error.localizedDescription)"
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
        try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
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
            // No bloqueamos la prueba por un fallo al cerrar la sesión.
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lockedPlayer = nil
            self.deactivateSession()
            self.status = flag
                ? "PRUEBA V3 TERMINADA. La frase debió sonar con el iPhone bloqueado por volumen multimedia."
                : "La reproducción V3 terminó de forma inesperada."
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
    private var silenceSeconds: Double = 12.0

    func generate(
        text: String,
        silenceSeconds: Double,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.completion = completion
        self.silenceSeconds = silenceSeconds

        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("sofpago_multimedia_bloqueado_v3.caf")
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
