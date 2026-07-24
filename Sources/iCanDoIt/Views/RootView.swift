import SwiftUI
import SwiftData

enum Screen {
    case ritual, today, review
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DayTask.sortOrder) private var allTasks: [DayTask]

    @State private var screen: Screen = .ritual
    @State private var decided = false

    private var todayKey: String { Date.now.dayKey }
    private var todayTasks: [DayTask] { allTasks.filter { $0.dayKey == todayKey } }
    private var stats: Stats { Stats.compute(from: allTasks) }

    var body: some View {
        ZStack {
            AppBackground()
            // 苹果式弹簧缩放切换;热力图已压扁成单层纹理,缩放不掉帧
            Group {
                switch screen {
                case .ritual:
                    MorningRitualView(onStart: startDay)
                        .transition(.appleZoom)
                case .today:
                    TodayView(tasks: todayTasks, stats: stats) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { screen = .review }
                    }
                    .transition(.appleZoom)
                case .review:
                    ReviewView(stats: stats) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { screen = .today }
                    }
                    .transition(.appleZoom)
                }
            }
        }
        // 全界面走英文(日期、时间格式也跟着走)
        .environment(\.locale, Locale(identifier: "en_US"))
        .onAppear {
            if !decided {
                decided = true
                screen = todayTasks.isEmpty ? .ritual : .today
            }
        }
    }

    private func startDay(_ drafts: [TaskDraft]) {
        for (i, d) in drafts.enumerated() {
            context.insert(DayTask(title: d.title, reward: d.reward, dayKey: todayKey, sortOrder: i))
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { screen = .today }
    }
}
