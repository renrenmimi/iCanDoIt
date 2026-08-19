import AppKit
import SwiftUI

enum Theme {
    static let bgTop = Color(red: 0.075, green: 0.065, blue: 0.145)
    static let bgBottom = Color(red: 0.02, green: 0.02, blue: 0.05)
    static let accentA = Color(red: 0.55, green: 0.36, blue: 0.96)   // 紫罗兰
    static let accentB = Color(red: 0.93, green: 0.28, blue: 0.60)   // 品红
    static let electricBlue = Color(red: 0.20, green: 0.45, blue: 0.95)
    static let mint = Color(red: 0.30, green: 0.87, blue: 0.68)
    static let amber = Color(red: 1.00, green: 0.72, blue: 0.30)
    static let urgent = Color(red: 0.99, green: 0.36, blue: 0.38)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.55)

    static let accentGradient = LinearGradient(
        colors: [accentA, accentB],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let successGradient = LinearGradient(
        colors: [mint, accentA],
        startPoint: .leading, endPoint: .trailing
    )
    /// 玻璃卡片的「边缘光」描边:左上亮、右下暗,模拟光从上方打在玻璃上
    static let edgeLight = LinearGradient(
        colors: [.white.opacity(0.30), .white.opacity(0.07), .white.opacity(0.02)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// 按钮顶部的高光描边
    static let buttonHighlight = LinearGradient(
        colors: [.white.opacity(0.55), .white.opacity(0.05)],
        startPoint: .top, endPoint: .bottom
    )
}

/// 真·毛玻璃:系统级 behind-window 模糊,透出桌面
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .fullScreenUI   // 比 hudWindow 更清透的一档模糊
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// 把窗口背景调成透明,让 behind-window 模糊生效
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isOpaque = false
            w.backgroundColor = .clear
            w.titlebarAppearsTransparent = true
            // 必须关掉:开着的话 AppKit 会把卡片上的拖拽手势当成"拖窗口",
            // 看板就没法拖卡片了。窗口仍可从顶部标题栏区域拖动。
            w.isMovableByWindowBackground = false
            w.appearance = NSAppearance(named: .darkAqua)
        }
        return v
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// 缓慢漂移的极光光斑(RadialGradient 实现,不用模糊滤镜,性能友好)
struct AuroraGlow: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                blob(Theme.accentA.opacity(0.40), 620,
                     x: -250 + 70 * sin(t / 9), y: -210 + 50 * cos(t / 7))
                blob(Theme.accentB.opacity(0.28), 560,
                     x: 310 + 80 * cos(t / 11), y: 240 + 60 * sin(t / 8))
                blob(Theme.electricBlue.opacity(0.22), 520,
                     x: 60 * sin(t / 13), y: 330 + 40 * cos(t / 10))
            }
        }
        .allowsHitTesting(false)
    }

    private func blob(_ color: Color, _ size: CGFloat, x: Double, y: Double) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [color, .clear],
                center: .center, startRadius: 0, endRadius: size / 2
            ))
            .frame(width: size, height: size)
            .offset(x: x, y: y)
    }
}

/// 全局背景:毛玻璃 + 深色染层 + 漂移极光
struct AppBackground: View {
    var body: some View {
        ZStack {
            if Snapshot.offscreen {
                LinearGradient(
                    colors: [Theme.bgTop, Theme.bgBottom],
                    startPoint: .top, endPoint: .bottom
                )
            } else {
                VisualEffectView()
                // 染色层压到最薄,壁纸的模糊光影是主角
                LinearGradient(
                    colors: [Theme.bgTop.opacity(0.22), Theme.bgBottom.opacity(0.34)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            AuroraGlow()
        }
        .ignoresSafeArea()
        .background(WindowChrome())
    }
}

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.white.opacity(0.035))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.edgeLight, lineWidth: 1)
            )
        // 不加投影:阴影会从半透明玻璃底下透出来,形成脏脏的光晕
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 11)
            .background(Theme.accentGradient, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.buttonHighlight, lineWidth: 1))
            .shadow(color: Theme.accentA.opacity(isEnabled ? 0.55 : 0), radius: 16, y: 5)
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .background(.white.opacity(0.04), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.edgeLight, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 34, height: 34)
            .background(.ultraThinMaterial, in: Circle())
            .background(.white.opacity(0.04), in: Circle())
            .overlay(Circle().strokeBorder(Theme.edgeLight, lineWidth: 1))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// ScrollView 的内容在 ImageRenderer 离屏渲染下会是空白,
/// 快照自检模式里退化成普通堆叠,好让界面能被验证
struct MaybeScroll<Content: View>: View {
    let axis: Axis.Set
    @ViewBuilder var content: () -> Content

    var body: some View {
        if Snapshot.offscreen {
            if axis == .horizontal {
                HStack(alignment: .top, spacing: 0) { content() }
            } else {
                VStack(spacing: 0) { content() }
            }
        } else {
            ScrollView(axis, showsIndicators: false) { content() }
        }
    }
}

/// 苹果式缩放淡入:进场从 104.5% 落到位,出场缩到 96.5%,配弹簧曲线
struct ScaleFadeModifier: ViewModifier {
    let scale: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content.scaleEffect(scale).opacity(opacity)
    }
}

extension AnyTransition {
    static var appleZoom: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: ScaleFadeModifier(scale: 1.045, opacity: 0),
                identity: ScaleFadeModifier(scale: 1, opacity: 1)
            ),
            removal: .modifier(
                active: ScaleFadeModifier(scale: 0.965, opacity: 0),
                identity: ScaleFadeModifier(scale: 1, opacity: 1)
            )
        )
    }
}

/// 大标题的衬底阴影:玻璃变透后保证亮色壁纸下文字依然清晰
struct LegibilityShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(0.38), radius: 10, y: 1)
    }
}

extension View {
    func legibilityShadow() -> some View { modifier(LegibilityShadow()) }
}

/// 「🎁 奖励」小胶囊标签
struct RewardChip: View {
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Text("🎁").font(.system(size: 10))
            // 单行 + 尾部省略:看板窄列里不会被挤成一列竖排字母
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}
