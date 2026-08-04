import SwiftUI
import SwiftData

enum Screen {
    case ritual, board, review
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DayTask.sortOrder) private var allTasks: [DayTask]
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    @State private var screen: Screen = .ritual
    @State private var scope: BoardScope = .today
    /// 当前浏览的周/月里的任意一天,用来翻页
    @State private var anchor: Date = .now
    /// 当前选中的板;nil = All(跨板汇总)
    @State private var project: String?
    @State private var decided = false

    private var todayBucket: String { BucketKey.day(.now) }

    /// 当前板筛选后的任务(All 模式下是全部)
    private var visibleTasks: [DayTask] {
        guard let project else { return allTasks }
        return allTasks.filter { $0.projectUID == project }
    }
    private var todayTasks: [DayTask] { visibleTasks.filter { $0.bucketKey == todayBucket } }
    /// 统计始终是跨板的:连击就是连击,不该被切板改变
    private var stats: Stats { Stats.compute(from: allTasks) }

    private var activeProjectUID: String {
        project ?? projects.first?.uid ?? ""
    }
    /// All 模式下才在卡片上标出板名
    private var projectBadges: [String: String] {
        guard project == nil, projects.count > 1 else { return [:] }
        return Dictionary(uniqueKeysWithValues: projects.map { ($0.uid, "\($0.emoji) \($0.name)") })
    }

    private var columns: [BoardColumn] {
        scope == .week
            ? BoardLayout.weekColumns(anchor: anchor)
            : BoardLayout.monthColumns(anchor: anchor)
    }

    var body: some View {
        ZStack {
            AppBackground()

            Group {
                switch screen {
                case .ritual:
                    MorningRitualView(onStart: startDay)
                        .transition(.appleZoom)

                case .board:
                    VStack(spacing: 14) {
                        TopBar(
                            scope: $scope,
                            anchor: $anchor,
                            streak: stats.currentStreak,
                            onShowReview: {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    screen = .review
                                }
                            }
                        )
                        .padding(.horizontal, 36)
                        .padding(.top, 34)

                        ProjectBar(
                            projects: projects,
                            tasks: allTasks,
                            selected: $project,
                            resolve: resolve
                        )
                        .padding(.horizontal, 36)

                        if scope == .today {
                            TodayView(
                                tasks: todayTasks, stats: stats,
                                activeProjectUID: activeProjectUID
                            )
                        } else {
                            BoardView(
                                scope: scope,
                                columns: columns,
                                tasks: visibleTasks,
                                activeProjectUID: activeProjectUID,
                                projectBadges: projectBadges,
                                resolve: resolve
                            )
                        }
                    }
                    .transition(.appleZoom)

                case .review:
                    ReviewView(stats: stats) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { screen = .board }
                    }
                    .transition(.appleZoom)
                }
            }
        }
        // 全界面走英文(日期、时间格式也跟着走)
        .environment(\.locale, .en)
        .onAppear {
            guard !decided else { return }
            decided = true
            Migration.backfill(tasks: allTasks, projects: projects, context: context)
            screen = todayTasks.isEmpty ? .ritual : .board
        }
    }

    /// 拖拽载荷是 uid 字符串,这里换回任务对象
    private func resolve(_ uid: String) -> DayTask? {
        allTasks.first { $0.uid == uid }
    }

    private func startDay(_ drafts: [TaskDraft]) {
        // 晨间仪式可能发生在第一次启动、板还没建出来的时刻
        let home = Migration.backfill(tasks: allTasks, projects: projects, context: context)
        for (i, d) in drafts.enumerated() {
            context.insert(DayTask(
                title: d.title, reward: d.reward,
                bucketKey: todayBucket, sortOrder: i,
                projectUID: project ?? home.uid
            ))
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { screen = .board }
    }
}

// MARK: - 顶部导航条

private struct TopBar: View {
    @Binding var scope: BoardScope
    @Binding var anchor: Date
    let streak: Int
    var onShowReview: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            scopeSwitcher

            if scope != .today {
                pager
            }

            Spacer(minLength: 0)

            if streak > 0 {
                streakChip
            }

            Button(action: onShowReview) {
                Image(systemName: "chart.bar.xaxis")
            }
            .buttonStyle(IconButtonStyle())
            .help("Review & stats")
        }
    }

    private var streakChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.amber)
                .symbolEffect(.pulse, options: .repeating)
            Text("\(streak)-day streak")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.amber.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.amber.opacity(0.25), lineWidth: 1))
    }

    private var scopeSwitcher: some View {
        HStack(spacing: 3) {
            ForEach(BoardScope.allCases) { s in
                let active = s == scope
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                        scope = s
                        anchor = .now
                    }
                } label: {
                    Text(s.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(active ? .white : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if active {
                                Capsule().fill(Theme.accentGradient)
                                    .shadow(color: Theme.accentA.opacity(0.45), radius: 8, y: 2)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.white.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.09), lineWidth: 1))
    }

    private var pager: some View {
        HStack(spacing: 6) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(MiniIconStyle())
                .help(scope == .week ? "Previous week" : "Previous month")

            Text(pagerLabel)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 96)
                .contentTransition(.opacity)

            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(MiniIconStyle())
                .help(scope == .week ? "Next week" : "Next month")

            if !isCurrentPeriod {
                Button("Now") {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { anchor = .now }
                }
                .buttonStyle(MiniButtonStyle(filled: false))
            }
        }
    }

    private var pagerLabel: String {
        scope == .week
            ? "Week \(Calendar.iso8601.component(.weekOfYear, from: anchor))"
            : anchor.formatted(.dateTime.month(.wide).year().locale(.en))
    }

    private var isCurrentPeriod: Bool {
        scope == .week
            ? BucketKey.week(anchor) == BucketKey.week(.now)
            : BucketKey.month(anchor) == BucketKey.month(.now)
    }

    private func shift(_ delta: Int) {
        let cal = Calendar.iso8601
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            if scope == .week {
                anchor = cal.date(byAdding: .day, value: delta * 7, to: anchor) ?? anchor
            } else {
                anchor = Calendar.current.date(byAdding: .month, value: delta, to: anchor) ?? anchor
            }
        }
    }
}

struct MiniIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 24, height: 24)
            .background(.white.opacity(0.06), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.09), lineWidth: 1))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
