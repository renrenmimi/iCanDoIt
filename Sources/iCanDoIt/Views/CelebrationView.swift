import SwiftUI

/// 只在当日任务全部完成时出现:Perfect Day 庆祝 + 今日全部奖励清单
struct CelebrationOverlay: View {
    let rewards: [String]
    var onClose: () -> Void

    @State private var showCard: Bool

    init(rewards: [String], startVisible: Bool = false, onClose: @escaping () -> Void) {
        self.rewards = rewards
        self.onClose = onClose
        self._showCard = State(initialValue: startVisible)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            ConfettiView(count: 220)

            VStack(spacing: 14) {
                Text("🏆")
                    .font(.system(size: 54))
                Text("Perfect Day!")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("You finished everything today")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)

                if !rewards.isEmpty {
                    VStack(spacing: 8) {
                        Text("Time to reward yourself")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                        ForEach(Array(rewards.enumerated()), id: \.offset) { _, reward in
                            HStack(spacing: 8) {
                                Text("🎁")
                                Text(reward)
                                    .lineLimit(2)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(Theme.accentB.opacity(0.14), in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.accentB.opacity(0.3), lineWidth: 1))
                        }
                    }
                    .padding(.top, 4)
                }

                Button(rewards.isEmpty ? "Awesome →" : "Claim my rewards →") {
                    onClose()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 34)
            .frame(minWidth: 340)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .background(
                Theme.bgTop.opacity(0.55),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.edgeLight, lineWidth: 1)
            )
            .shadow(color: Theme.accentA.opacity(0.35), radius: 50, y: 10)
            .shadow(color: .black.opacity(0.5), radius: 40, y: 18)
            .scaleEffect(showCard ? 1 : 0.68)
            .opacity(showCard ? 1 : 0)
        }
        .onAppear {
            // 弹性更足的入场:轻微过冲再回弹,iOS 弹窗的手感
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                showCard = true
            }
        }
    }
}

/// 彩带粒子雨:纯 SwiftUI Canvas,无第三方依赖
struct ConfettiView: View {
    struct Particle {
        let x: CGFloat
        let vx: CGFloat
        let vy: CGFloat
        let size: CGFloat
        let spin: Double
        let delay: Double
        let colorIndex: Int
        let shape: Int
    }

    private static let palette: [Color] = [Theme.accentA, Theme.accentB, Theme.mint, Theme.amber, .white]

    private let particles: [Particle]
    private let start = Date()

    init(count: Int) {
        particles = (0..<count).map { _ in
            Particle(
                x: CGFloat.random(in: 0...1),
                vx: CGFloat.random(in: -50...50),
                vy: CGFloat.random(in: 60...220),
                size: CGFloat.random(in: 6...13),
                spin: Double.random(in: -7...7),
                delay: Double.random(in: 0...0.6),
                colorIndex: Int.random(in: 0..<Self.palette.count),
                shape: Int.random(in: 0...2)
            )
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in particles {
                    let pt = t - p.delay
                    guard pt > 0, pt < 3.5 else { continue }
                    let y = -24 + p.vy * pt + 0.5 * 320 * pt * pt
                    guard y < size.height + 30 else { continue }
                    let x = p.x * size.width + p.vx * pt
                    let fade = max(0.0, min(1.0, (3.2 - pt) / 0.8))

                    var c = ctx
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin * pt))
                    let rect = CGRect(
                        x: -p.size / 2, y: -p.size / 2,
                        width: p.size,
                        height: p.shape == 0 ? p.size * 0.55 : p.size
                    )
                    let path = p.shape == 2
                        ? Path(ellipseIn: rect)
                        : Path(roundedRect: rect, cornerRadius: 2)
                    c.fill(path, with: .color(Self.palette[p.colorIndex]))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
