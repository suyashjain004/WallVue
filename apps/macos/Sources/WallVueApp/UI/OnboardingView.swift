import SwiftUI
import WallVueCore

/// First-run tour: four short cards, each with at most one choice.
struct OnboardingView: View {
    let onFinish: () -> Void

    @AppStorage(SettingsKey.pauseOnBattery) private var pauseOnBattery = false
    @AppStorage(SettingsKey.syncStillToSystem) private var syncStillToSystem = true
    @State private var step = 0
    @State private var openAtLogin = false

    private struct Card {
        let symbol: String
        let title: String
        let text: String
        let colors: [Color]
    }

    private let cards = [
        Card(symbol: "sparkles.tv", title: "Welcome to WallVue",
             text: "Live wallpapers for your Mac. A quick tour, then you're in.",
             colors: [Color(red: 0.10, green: 0.25, blue: 0.55), Color(red: 0.03, green: 0.05, blue: 0.12)]),
        Card(symbol: "power", title: "Open at Login",
             text: "Start WallVue when you log in, so your wallpaper is already playing.",
             colors: [Color(red: 0.08, green: 0.35, blue: 0.22), Color(red: 0.02, green: 0.07, blue: 0.06)]),
        Card(symbol: "battery.75percent", title: "Battery",
             text: "Save power by holding the wallpaper still while your Mac is unplugged.",
             colors: [Color(red: 0.32, green: 0.22, blue: 0.48), Color(red: 0.05, green: 0.04, blue: 0.10)]),
        Card(symbol: "lock.display", title: "Lock Screen",
             text: "Keep the Lock Screen matching your desktop with a still of the wallpaper.",
             colors: [Color(red: 0.45, green: 0.24, blue: 0.16), Color(red: 0.09, green: 0.04, blue: 0.04)]),
        Card(symbol: "display.2", title: "Live on Every Display",
             text: "Set a wallpaper in one click. Every connected display plays it.",
             colors: [Color(red: 0.07, green: 0.30, blue: 0.40), Color(red: 0.02, green: 0.06, blue: 0.09)]),
    ]

    var body: some View {
        let card = cards[step]

        ZStack {
            LinearGradient(colors: card.colors, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if step > 0 {
                        Button { step -= 1 } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(CircleButtonStyle())
                            .accessibilityLabel("Back")
                    }
                    Spacer()
                    Button("Skip") { onFinish() }
                        .buttonStyle(PillButtonStyle())
                }

                Spacer()
                Image(systemName: card.symbol)
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                Spacer()

                Text(card.title)
                    .font(.system(size: 30, weight: .bold))
                Text(card.text)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)

                control
                    .padding(.top, 18)

                Button {
                    if step < cards.count - 1 { step += 1 } else { onFinish() }
                } label: {
                    Text(step == 0 ? "Get Started" : (step == cards.count - 1 ? "Done" : "Continue"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(prominent: true, large: true))
                .keyboardShortcut(.defaultAction)
                .padding(.top, 18)
            }
            .padding(28)
        }
        .frame(width: 460, height: 600)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: step)
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }

    @ViewBuilder
    private var control: some View {
        switch step {
        case 1:
            row("Start WallVue at login", symbol: "power", isOn: Binding(
                get: { openAtLogin },
                set: { newValue in
                    try? LoginItem.set(newValue)
                    openAtLogin = LoginItem.isEnabled
                }
            ))
        case 2:
            row("Pause on battery", symbol: "battery.25percent", isOn: $pauseOnBattery)
        case 3:
            row("Match the Lock Screen", symbol: "lock", isOn: $syncStillToSystem)
        default:
            EmptyView()
        }
    }

    private func row(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
