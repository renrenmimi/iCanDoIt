import SwiftUI

struct ReviewView: View {
    var stats: Stats
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(IconButtonStyle())
                .help("Back to Today")
                Text("Review")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .legibilityShadow()
                Spacer()
            }

            HStack(spacing: 14) {
                statCard(icon: "checkmark.seal.fill", value: "\(stats.totalDone)", label: "Total Done", tint: Theme.accentA)
                statCard(icon: "flame.fill", value: "\(stats.currentStreak)", label: "Current Streak", tint: Theme.amber)
                statCard(icon: "bolt.fill", value: "\(stats.longestStreak)", label: "Best Streak", tint: Theme.accentB)
                statCard(icon: "trophy.fill", value: "\(stats.perfectDays)", label: "Perfect Days", tint: Theme.mint)
            }

            heatmapCard

            Spacer()
        }
        .padding(.horizontal, 36)
        .padding(.top, 48)
        .padding(.bottom, 28)
    }

    private func statCard(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.7), radius: 8)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassCard(cornerRadius: 16)
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Consistency Map · Last 6 Months")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                legend
            }
            HeatmapGrid(doneByDay: stats.doneByDay)
        }
        .padding(20)
        .glassCard(cornerRadius: 18)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(HeatmapGrid.color(for: level))
                    .frame(width: 10, height: 10)
            }
            Text("More")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct HeatmapGrid: View {
    let doneByDay: [String: Int]

    private let weeks = 26
    private let cellSize: CGFloat = 15
    private let gap: CGFloat = 4
    private var pitch: CGFloat { cellSize + gap }

    @State private var hoverCol: Int
    @State private var hoverRow: Int

    init(doneByDay: [String: Int], debugHover: (col: Int, row: Int)? = nil) {
        self.doneByDay = doneByDay
        _hoverCol = State(initialValue: debugHover?.col ?? -1)
        _hoverRow = State(initialValue: debugHover?.row ?? -1)
    }

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: .now) }
    private var startDate: Date {
        cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: today) ?? today
    }

    var body: some View {
        GridCells(doneByDay: doneByDay, weeks: weeks, cellSize: cellSize, gap: gap)
            // 自定义悬停:整个网格只挂一个监听,数学换算出格子,零延迟
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    let c = Int(p.x / pitch)
                    let r = Int(p.y / pitch)
                    let inX = p.x - CGFloat(c) * pitch
                    let inY = p.y - CGFloat(r) * pitch
                    if c >= 0, c < weeks, r >= 0, r < 7, inX <= cellSize, inY <= cellSize {
                        hoverCol = c; hoverRow = r
                    } else {
                        hoverCol = -1; hoverRow = -1
                    }
                case .ended:
                    hoverCol = -1; hoverRow = -1
                }
            }
            // 高亮框和提示牌各自独立锚定网格左上角:
            // 放进同一个 overlay 会被打包成组导致坐标偏移(白框跑到右边的 bug)
            .overlay(alignment: .topLeading) {
                if hoverCol >= 0, hoverRow >= 0 { hoverHighlight }
            }
            .overlay(alignment: .topLeading) {
                if hoverCol >= 0, hoverRow >= 0 { tooltip }
            }
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var hoverDate: Date {
        cal.date(byAdding: .day, value: hoverCol * 7 + hoverRow, to: startDate) ?? startDate
    }

    private var hoverHighlight: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
            .frame(width: cellSize, height: cellSize)
            .offset(x: CGFloat(hoverCol) * pitch, y: CGFloat(hoverRow) * pitch)
            .allowsHitTesting(false)
    }

    private var tooltip: some View {
        let count = doneByDay[hoverDate.dayKey] ?? 0
        let dateStr = hoverDate.formatted(
            .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(Locale(identifier: "en_US"))
        )
        let gridWidth = CGFloat(weeks) * pitch - gap
        let rawX = CGFloat(hoverCol) * pitch + cellSize / 2 - 65
        let x = min(max(0, rawX), gridWidth - 130)
        // 靠上两行的格子,提示牌翻到下方,避免顶出卡片
        let y = hoverRow < 2
            ? CGFloat(hoverRow) * pitch + cellSize + 8
            : CGFloat(hoverRow) * pitch - 34

        return HStack(spacing: 6) {
            Text(dateStr)
                .foregroundStyle(Theme.textPrimary)
            Text(count > 0 ? "\(count) done" : "No activity")
                .foregroundStyle(count > 0 ? Theme.mint : Theme.textSecondary)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(red: 0.1, green: 0.08, blue: 0.18).opacity(0.96), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.edgeLight, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        .fixedSize()
        .offset(x: x, y: y)
        .allowsHitTesting(false)
    }

    static func color(for count: Int) -> Color {
        switch count {
        case 0: return .white.opacity(0.06)
        case 1: return Theme.accentA.opacity(0.35)
        case 2: return Theme.accentA.opacity(0.55)
        case 3: return Theme.accentA.opacity(0.8)
        default: return Theme.accentB
        }
    }
}

/// 纯展示的格子层:不感知悬停状态,避免鼠标移动时反复重绘 182 个格子
private struct GridCells: View {
    let doneByDay: [String: Int]
    let weeks: Int
    let cellSize: CGFloat
    let gap: CGFloat

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: today) ?? today

        HStack(alignment: .top, spacing: gap) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { d in
                        let date = cal.date(byAdding: .day, value: w * 7 + d, to: start) ?? start
                        cell(date: date, isToday: cal.isDate(date, inSameDayAs: today))
                    }
                }
            }
        }
        // 182 个带阴影的格子压扁成一张 GPU 纹理,切换动画只搬运一层
        .drawingGroup()
    }

    private func cell(date: Date, isToday: Bool) -> some View {
        let count = doneByDay[date.dayKey] ?? 0
        return RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(HeatmapGrid.color(for: count))
            .shadow(
                color: count >= 3 ? Theme.accentB.opacity(0.55) : .clear,
                radius: count >= 3 ? 4 : 0
            )
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                }
            }
    }
}
