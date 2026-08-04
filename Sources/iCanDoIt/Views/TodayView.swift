import AppKit
import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    var tasks: [DayTask]
    var stats: Stats
    /// 在 Today 页新建的任务归到哪个板
    var activeProjectUID: String = ""

    @State private var showCelebration = false
    @State private var showAdd = false

    private var doneCount: Int { tasks.filter(\.isDone).count }

    // 主流待办的通用惯例:未完成置顶按创建顺序,完成的沉底按完成时间
    private var pending: [DayTask] {
        tasks.filter { !$0.isDone }.sorted { $0.sortOrder < $1.sortOrder }
    }
    private var finished: [DayTask] {
        tasks.filter(\.isDone)
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }
    private var displayTasks: [DayTask] { pending + finished }

    /// 今天所有写了奖励的任务的奖励清单(按完成顺序)
    private var todayRewards: [String] {
        finished.map(\.reward).filter { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 22) {
                header
                progressBar
                taskList
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 28)

            if showCelebration {
                CelebrationOverlay(rewards: todayRewards) {
                    withAnimation(.easeOut(duration: 0.25)) { showCelebration = false }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddTaskSheet { title, reward in
                addTask(title: title, reward: reward)
            }
        }
    }

    // MARK: - 头部

    private var headline: String {
        if tasks.isEmpty { return "Nothing planned yet" }
        if doneCount == tasks.count { return "All done today ✨" }
        if doneCount == 0 { return "A fresh day. Let's go ☀️" }
        return "Nice progress, keep going 💪"
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(DateInfo.todayString)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Text(headline)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.opacity)
                    .legibilityShadow()
            }
            Spacer()
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(IconButtonStyle())
            .help("Add a task")
        }
    }

    // MARK: - 进度条

    private var progressBar: some View {
        HStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    if !tasks.isEmpty && doneCount > 0 {
                        Capsule()
                            .fill(doneCount == tasks.count ? Theme.successGradient : Theme.accentGradient)
                            .frame(width: max(6, geo.size.width * CGFloat(doneCount) / CGFloat(tasks.count)))
                            .shadow(
                                color: (doneCount == tasks.count ? Theme.mint : Theme.accentB).opacity(0.65),
                                radius: 6, y: 0
                            )
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: doneCount)
            }
            .frame(height: 6)
            Text("\(doneCount)/\(tasks.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(doneCount)))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: doneCount)
        }
    }

    // MARK: - 任务列表

    private var taskList: some View {
        Group {
            if tasks.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textSecondary)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    Text("Add your first thing for today")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    Button("Add Task") { showAdd = true }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MaybeScroll(axis: .vertical) {
                    VStack(spacing: 10) {
                        ForEach(displayTasks) { task in
                            // 「已完成」小标题跟着第一条完成任务走,
                            // 保持单个 ForEach,打勾时行的下沉动画不断裂
                            VStack(alignment: .leading, spacing: 10) {
                                if task.persistentModelID == finished.first?.persistentModelID {
                                    finishedHeader
                                }
                                TaskRow(
                                    task: task,
                                    onToggle: { toggle(task) },
                                    onDelete: { delete(task) }
                                )
                            }
                        }
                    }
                    .padding(2)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var finishedHeader: some View {
        FinishedHeader(count: finished.count)
    }

    // MARK: - 操作

    private func toggle(_ task: DayTask) {
        if task.isDone {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                task.completedAt = nil
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                task.completedAt = .now
            }
            // 触控板的轻微触觉反馈,像原生 App 一样"有手感"
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            // 庆祝动画只在当日任务全部完成时出现
            if tasks.allSatisfy(\.isDone) {
                withAnimation(.easeIn(duration: 0.2)) { showCelebration = true }
            }
        }
    }

    private func delete(_ task: DayTask) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            context.delete(task)
        }
    }

    private func addTask(title: String, reward: String) {
        guard !title.isEmpty else { return }
        let maxOrder = tasks.map(\.sortOrder).max() ?? -1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            context.insert(DayTask(
                title: title, reward: reward,
                bucketKey: BucketKey.day(.now), sortOrder: maxOrder + 1,
                projectUID: activeProjectUID
            ))
        }
    }
}

// MARK: - 「已完成」分组小标题

struct FinishedHeader: View {
    let count: Int
    var body: some View {
        HStack(spacing: 10) {
            Text("Completed · \(count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
        .padding(.top, 8)
    }
}

// MARK: - 任务行

struct TaskRow: View {
    let task: DayTask
    var onToggle: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(task.isDone ? .clear : .white.opacity(hovering ? 0.5 : 0.28), lineWidth: 1.5)
                    if task.isDone {
                        Circle().fill(Theme.accentGradient)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, value: task.isDone)
                    }
                }
                .frame(width: 24, height: 24)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(task.isDone ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(task.isDone, color: Theme.textSecondary)
                    .lineLimit(2)
                if !task.reward.isEmpty {
                    RewardChip(text: task.reward)
                }
            }

            Spacer()

            if task.isDone, let at = task.completedAt {
                Text(at.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }

            // 常驻布局、只变透明度:悬停时不会挤动旁边的内容
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .help("Delete")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .glassCard(cornerRadius: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(hovering ? 0.15 : 0), lineWidth: 1)
        }
        .opacity(task.isDone ? 0.7 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            if task.isDone {
                Button("Mark as Not Done", action: onToggle)
            }
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
