import SwiftUI

struct ContentView: View {
    @StateObject private var manager = SpeechNotificationManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 72))

                Text("SOFFAST")
                    .font(.system(size: 31, weight: .bold))

                Text("Pago Sonoro · iPhone")
                    .font(.title2.weight(.semibold))

                Text("Prueba nativa gratuita")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Frase de prueba")
                        .font(.headline)

                    Text("“Pago recibido de Walter, diez soles.”")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                Button {
                    manager.testVoiceNow()
                } label: {
                    Label("Escuchar voz ahora", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    Task {
                        await manager.scheduleLockedPhoneTest()
                    }
                } label: {
                    Label("Probar con iPhone bloqueado", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(manager.isWorking)

                Text(manager.status)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(manager.lastSucceeded ? .green : .secondary)

                if manager.countdownHint {
                    Text("Bloquea el iPhone ahora. El aviso llegará en 10 segundos.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Text("Para esta prueba: volumen audible y modo silencio desactivado.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .navigationTitle("Pago Sonoro")
            .task {
                await manager.requestNotificationPermission()
            }
        }
    }
}
