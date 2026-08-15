import SwiftUI

// MARK: - Intro / Onboarding
//
// A first-launch, animated walkthrough that introduces new users to the
// main features of BikeMap SJC. It is shown once and gated by the
// `hasSeenIntro` flag in UserDefaults (see `BikeMapSJCApp`).

struct IntroView: View {

    /// Called when the user finishes or skips the walkthrough.
    var onFinish: () -> Void

    @State private var page = 0
    @State private var animateBackground = false

    private let pages = IntroPage.all

    var body: some View {
        ZStack {
            animatedBackground

            VStack(spacing: 0) {

                // Skip button
                HStack {
                    Spacer()
                    Button {
                        finish()
                    } label: {
                        Text("Pular")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .opacity(page == pages.count - 1 ? 0 : 1)
                    .animation(.easeInOut(duration: 0.25), value: page)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // Feature pages
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        IntroPageView(page: item, isCurrent: index == page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Progress dots
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? pages[page].tint : Color.secondary.opacity(0.3))
                            .frame(width: i == page ? 22 : 8, height: 8)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: page)
                    }
                }
                .padding(.bottom, 24)

                // Primary action button
                Button {
                    advance()
                } label: {
                    Text(page == pages.count - 1 ? "Começar" : "Próximo")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(pages[page].tint.gradient, in: RoundedRectangle(cornerRadius: 16))
                        .shadow(color: pages[page].tint.opacity(0.35), radius: 10, x: 0, y: 6)
                        .animation(.easeInOut(duration: 0.3), value: page)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear { animateBackground = true }
    }

    // MARK: Actions

    private func advance() {
        if page < pages.count - 1 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                page += 1
            }
        } else {
            finish()
        }
    }

    private func finish() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeInOut(duration: 0.35)) {
            onFinish()
        }
    }

    // MARK: Background

    private var animatedBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.85, green: 0.93, blue: 1.0),
                pages[page].tint.opacity(0.18),
                Color(red: 0.90, green: 0.96, blue: 1.0)
            ],
            startPoint: animateBackground ? .topLeading : .bottomLeading,
            endPoint: animateBackground ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: page)
        .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: animateBackground)
    }
}

// MARK: - Single page

private struct IntroPageView: View {
    let page: IntroPage
    let isCurrent: Bool

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Hero icon
            ZStack {
                Circle()
                    .fill(page.tint.opacity(0.15))
                    .frame(width: 200, height: 200)
                    .scaleEffect(appeared ? 1 : 0.6)

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 150, height: 150)
                    .shadow(color: page.tint.opacity(0.25), radius: 20, x: 0, y: 10)

                heroSymbol
            }
            .scaleEffect(appeared ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)

            // Text
            VStack(spacing: 14) {
                Text(page.title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)

            Spacer()
            Spacer()
        }
        .onChange(of: isCurrent) { _, current in
            if current { triggerAppear() } else { appeared = false }
        }
        .onAppear { if isCurrent { triggerAppear() } }
    }

    @ViewBuilder
    private var heroSymbol: some View {
        if let image = page.image {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 22))
        } else {
            Image(systemName: page.systemIcon)
                .font(.system(size: 62, weight: .semibold))
                .foregroundStyle(page.tint.gradient)
                .symbolEffectBounceIfAvailable(isCurrent)
        }
    }

    private func triggerAppear() {
        appeared = false
        withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.05)) {
            appeared = true
        }
    }
}

// MARK: - Page model

private struct IntroPage {
    let systemIcon: String
    let image: String?        // asset name (used instead of a symbol when present)
    let title: String
    let subtitle: String
    let tint: Color

    init(systemIcon: String = "", image: String? = nil, title: String, subtitle: String, tint: Color) {
        self.systemIcon = systemIcon
        self.image = image
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
    }

    static let all: [IntroPage] = [
        IntroPage(
            image: "logo",
            title: "Bem-vindo ao BikeMap SJC",
            subtitle: "O mapa cicloviário colaborativo de São José dos Campos, feito por ciclistas para ciclistas. 🚲",
            tint: Color(red: 0.10, green: 0.55, blue: 0.95)
        ),
        IntroPage(
            systemIcon: "map.fill",
            title: "Toda a malha cicloviária",
            subtitle: "Veja ciclovias, ciclofaixas e vias compartilhadas da cidade em um mapa interativo e sempre atualizado.",
            tint: Color(red: 0.10, green: 0.55, blue: 0.95)
        ),
        IntroPage(
            systemIcon: "square.3.layers.3d.down.right.fill",
            title: "Camadas sob seu controle",
            subtitle: "Abra o menu lateral e ative apenas as camadas que interessam a você — infraestrutura e pontos de interesse.",
            tint: Color(red: 0.55, green: 0.30, blue: 0.90)
        ),
        IntroPage(
            systemIcon: "mappin.and.ellipse",
            title: "Pontos úteis por perto",
            subtitle: "Encontre paraciclos, bombas de ar, lojas e pontos de reparo espalhados pela cidade.",
            tint: Color(red: 0.90, green: 0.50, blue: 0.10)
        ),
        IntroPage(
            systemIcon: "exclamationmark.shield.fill",
            title: "Alertas de furto em tempo real",
            subtitle: "Reporte furtos de bicicleta e receba avisos instantâneos quando algo acontecer na sua região.",
            tint: Color(red: 0.86, green: 0.20, blue: 0.25)
        ),
        IntroPage(
            systemIcon: "trophy.fill",
            title: "Contribua e ganhe pontos",
            subtitle: "Adicione pontos ao mapa, ajude a comunidade e suba no ranking dos ciclistas de SJC.",
            tint: Color(red: 0.10, green: 0.64, blue: 0.35)
        )
    ]
}

// MARK: - Symbol effect helper (graceful on older OS)

private extension View {
    @ViewBuilder
    func symbolEffectBounceIfAvailable(_ active: Bool) -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.bounce, options: .speed(0.8), value: active)
        } else {
            self
        }
    }
}
