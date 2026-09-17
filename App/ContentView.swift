import SwiftUI
import AVFoundation
import UIKit

struct ContentView: View {
    @StateObject private var manager = PagoTestManager()

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 72))

            Text("SofPago")
                .font(.largeTitle.bold())

            Text("Audio multimedia iPhone V2")
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

            Text("Pulsa la segunda opción y bloquea el iPhone. SofPago conservará tiempo de ejecución en segundo plano y reproducirá la voz por el canal multimedia después de 12 segundos.")
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
    private var scheduledWorkItem: DispatchWorkItem?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var lockedTestActive = false

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func speakNow() {
        stopPendingLockedTest()
        synthesizer.stopSpeaking(at: .immediate)

        do {
            try activateMultimediaSession()
            speakPaymentPhrase()
            status = "Reproduciendo por audio multimedia: Yape, Walter, diez soles."
        } catch {
            status = "No se pudo activar el audio multimedia: \(error.localizedDescription)"
        }
    }

    func prepareLockedMultimediaTest() {
        stopPendingLockedTest()
        synthesizer.stopSpeaking(at: .immediate)

        do {
            try activateMultimediaSession()
        } catch {
            status = "No se pudo activar el audio multimedia: \(error.localizedDescription)"
            return
        }

        lockedTestActive = true
        beginBackgroundExecution()

        guard backgroundTask != .invalid else {
            lockedTestActive = false
            status = "iOS no concedió tiempo de ejecución en segundo plano."
            return
        }

        status = "LISTO: bloquea el iPhone ahora. La voz multimedia sonará en 12 segundos."

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.lockedTestActive else { return }
            self.scheduledWorkItem = nil
            self.speakPaymentPhrase()
            self.status = "Reproduciendo con el iPhone bloqueado por volumen multimedia."
        }

        scheduledWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    func stopTest() {
        stopPendingLockedTest()
        synthesizer.stopSpeaking(at: .immediate)
        deactivateSession()
        status = "Prueba detenida."
    }

    private func activateMultimediaSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers])
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

    private func beginBackgroundExecution() {
        endBackgroundExecution()

        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SofPagoLockedAudioTest") { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.scheduledWorkItem?.cancel()
                self.scheduledWorkItem = nil
                self.lockedTestActive = false
                self.status = "iOS terminó el tiempo de segundo plano antes de reproducir la voz."
                self.endBackgroundExecution()
            }
        }
    }

    private func stopPendingLockedTest() {
        scheduledWorkItem?.cancel()
        scheduledWorkItem = nil
        lockedTestActive = false
        endBackgroundExecution()
    }

    private func endBackgroundExecution() {
        guard backgroundTask != .invalid else { return }
        let task = backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // La desactivación no debe bloquear la prueba.
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if self.lockedTestActive {
                self.lockedTestActive = false
                self.endBackgroundExecution()
                self.deactivateSession()
                self.status = "PRUEBA TERMINADA. Debió sonar bloqueado usando el volumen multimedia."
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.lockedTestActive {
                self.lockedTestActive = false
                self.endBackgroundExecution()
            }
        }
    }
}
