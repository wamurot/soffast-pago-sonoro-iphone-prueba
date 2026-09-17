import SwiftUI
import AVFoundation
import AudioToolbox

struct ContentView: View {
    @StateObject private var manager = PagoTestManager()

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 72))

            Text("SofPago")
                .font(.largeTitle.bold())

            Text("Audio multimedia iPhone V1")
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

            Text("La segunda opción activa el motor de audio multimedia. Tendrás 12 segundos para bloquear el iPhone. La voz debe obedecer al volumen multimedia, no a Timbre y alertas.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}

final class PagoTestManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var status = "Prueba primero la voz. Luego prueba con el iPhone bloqueado."

    private let synthesizer = AVSpeechSynthesizer()
    private let keepAliveEngine = AVAudioEngine()
    private var silentSourceNode: AVAudioSourceNode?
    private var scheduledWorkItem: DispatchWorkItem?
    private var stopEngineAfterSpeech = false

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func speakNow() {
        cancelScheduledSpeech()

        do {
            try activateMultimediaSession()
            speakPaymentPhrase()
            status = "Reproduciendo por audio multimedia: Yape, Walter, diez soles."
        } catch {
            status = "No se pudo activar el audio multimedia: \(error.localizedDescription)"
        }
    }

    func prepareLockedMultimediaTest() {
        cancelScheduledSpeech()
        synthesizer.stopSpeaking(at: .immediate)

        do {
            try activateMultimediaSession()
            try startBackgroundAudioEngine()

            stopEngineAfterSpeech = true
            status = "LISTO: motor multimedia activo. Bloquea el iPhone ahora. La voz sonará en 12 segundos."

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.scheduledWorkItem = nil
                self.speakPaymentPhrase()
                self.status = "Reproduciendo con iPhone bloqueado por el canal multimedia."
            }

            scheduledWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
        } catch {
            stopBackgroundAudioEngine()
            status = "No se pudo iniciar el audio en segundo plano: \(error.localizedDescription)"
        }
    }

    func stopTest() {
        cancelScheduledSpeech()
        synthesizer.stopSpeaking(at: .immediate)
        stopEngineAfterSpeech = false
        stopBackgroundAudioEngine()
        deactivateSession()
        status = "Prueba detenida."
    }

    private func activateMultimediaSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
    }

    private func speakPaymentPhrase() {
        let utterance = AVSpeechUtterance(string: "Yape, Walter, diez soles.")
        utterance.voice = AVSpeechSynthesisVoice(language: "es-PE")
            ?? AVSpeechSynthesisVoice(language: "es-ES")
        utterance.rate = 0.48
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    private func startBackgroundAudioEngine() throws {
        guard !keepAliveEngine.isRunning else { return }

        if silentSourceNode == nil {
            let source = AVAudioSourceNode { _, _, _, audioBufferList -> OSStatus in
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                for buffer in buffers {
                    if let data = buffer.mData, buffer.mDataByteSize > 0 {
                        memset(data, 0, Int(buffer.mDataByteSize))
                    }
                }
                return noErr
            }

            silentSourceNode = source
            keepAliveEngine.attach(source)
            keepAliveEngine.connect(source, to: keepAliveEngine.mainMixerNode, format: nil)
        }

        keepAliveEngine.prepare()
        try keepAliveEngine.start()
    }

    private func stopBackgroundAudioEngine() {
        if keepAliveEngine.isRunning {
            keepAliveEngine.stop()
        }

        if let source = silentSourceNode {
            keepAliveEngine.disconnectNodeOutput(source)
            keepAliveEngine.detach(source)
            silentSourceNode = nil
        }
    }

    private func cancelScheduledSpeech() {
        scheduledWorkItem?.cancel()
        scheduledWorkItem = nil
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // No bloqueamos la prueba por un fallo al desactivar la sesión.
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard stopEngineAfterSpeech else { return }
        stopEngineAfterSpeech = false
        stopBackgroundAudioEngine()
        deactivateSession()

        DispatchQueue.main.async { [weak self] in
            self?.status = "PRUEBA TERMINADA. Compara el volumen con Escuchar voz ahora."
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if stopEngineAfterSpeech {
            stopEngineAfterSpeech = false
            stopBackgroundAudioEngine()
            deactivateSession()
        }
    }
}
