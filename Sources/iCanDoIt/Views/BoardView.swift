import AppKit
import SwiftUI
import SwiftData

/// Trello 式看板:横向若干列,卡片可在列间拖动
struct BoardView: View {
    @Environment(\.modelContext) private var context

    let scope: BoardScope
    let columns: [BoardColumn]
    let tasks: [DayTask]
    /// 拖拽落下时由父层解析 uid → 任务
    let resolve: (String) -> DayTask?

    @State private var dragOverColumn: String?
    @State private var addingTo: String?
    @State private var draftTitle = ""
    @State private var draftReward = ""
    @FocusState private var draftFocused: Bool

    /// 离屏快照模式下不挂拖拽修饰符,否则 ImageRenderer 会画一堆 🚫 占位符
    private var interactive: Bool { !Snapshot.offscreen }

    var body: some View {
        // 列宽自适应:一周 7 天 + 目标列始终同屏可见,不需要横向滚动
        HStack(alignment: .top, spacing: 10) {
            ForEach(columns) { column in
                columnView(column)
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 22)
    }

    // MARK: - 单列

    private func columnView(_ column: BoardColumn) -> some View {
        let items = cards(in: column.id)
        let doneCount = items.filter(\.isDone).count
        let isOver = dragOverColumn == column.id

        return VStack(alignment: .leading, spacing: 10) {
            columnHeader(column, total: items.count, done: doneCount)

            MaybeScroll(axis: .vertical) {
                VStack(spacing: 7) {
                    ForEach(items) { task in
                        TaskCard(task: task, isCompact: true) {
                            toggle(task)
                        } onDelete: {
                            delete(task)
                        }
                        .modifier(CardDraggable(uid: task.uid, enabled: interactive))
                        // 落在某张卡片上 = 插到它前面
                        .modifier(CardDropTarget(enabled: interactive, onDrop: { uids in
                            move(uids: uids, to: column.id, before: task)
                        }, onTarget: { over in
                            if over { dragOverColumn = column.id }
                        }))
                    }

                    if addingTo == column.id {
                        inlineComposer(column)
                    } else {
                        addCardButton(column)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        // 等高列(Trello 的观感),内容不够高时列身依然铺满
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(9)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(column.isGoalColumn
                      ? Theme.accentA.opacity(isOver ? 0.20 : 0.10)
                      : .white.opacity(isOver ? 0.10 : 0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isOver ? Theme.mint.opacity(0.85)
                    : column.isToday ? Theme.accentB.opacity(0.55)
                    : .white.opacity(0.08),
                    lineWidth: isOver ? 1.6 : 1
                )
        }
        // 落在列的空白处 = 追加到末尾
        .modifier(CardDropTarget(enabled: interactive, onDrop: { uids in
            move(uids: uids, to: column.id, before: nil)
        }, onTarget: { over in
            dragOverColumn = over ? column.id : (dragOverColumn == column.id ? nil : dragOverColumn)
        }))
        .animation(.easeOut(duration: 0.15), value: isOver)
    }

    private func columnHeader(_ column: BoardColumn, total: Int, done: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if column.isGoalColumn {
                    Image(systemName: "target")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accentA)
                }
                Text(column.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                if column.isToday {
                    Text("TODAY")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.accentGradient, in: Capsule())
                }
                Spacer(minLength: 0)
                if total > 0 {
                    Text("\(done)/\(total)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(done == total ? Theme.mint : Theme.textSecondary)
                        .monospacedDigit()
                }
            }
            Text(column.subtitle)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Theme.textSecondary)

            // 月视图:把这一周里的日任务汇总出来,不然缩放到月视角就看不见它们了
            if !column.dayBuckets.isEmpty {
                let dayTasks = tasks.filter { column.dayBuckets.contains($0.bucketKey) }
                if !dayTasks.isEmpty {
                    let dayDone = dayTasks.filter(\.isDone).count
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 8))
                        Text("\(dayDone)/\(dayTasks.count) daily")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(dayDone == dayTasks.count ? Theme.mint : Theme.textSecondary)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    // MARK: - 加卡片

    private func addCardButton(_ column: BoardColumn) -> some View {
        Button {
            draftTitle = ""
            draftReward = ""
            addingTo = column.id
            draftFocused = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("Add card")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func inlineComposer(_ column: BoardColumn) -> some View {
        VStack(spacing: 6) {
            TextField("What needs doing?", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .focused($draftFocused)
                .onSubmit { commitDraft(to: column.id) }
            Divider().overlay(.white.opacity(0.08))
            TextField("🎁 Reward (optional)", text: $draftReward)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .onSubmit { commitDraft(to: column.id) }
            HStack(spacing: 6) {
                Button("Add") { commitDraft(to: column.id) }
                    .buttonStyle(MiniButtonStyle(filled: true))
                    .disabled(draftTitle.trimmed.isEmpty)
                Button("Cancel") { addingTo = nil }
                    .buttonStyle(MiniButtonStyle(filled: false))
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
            }
        }
        .padding(9)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.accentA.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - 数据操作

    private func cards(in bucket: String) -> [DayTask] {
        BoardMove.ordered(tasks, in: bucket)
    }

    private func commitDraft(to bucket: String) {
        let title = draftTitle.trimmed
        guard !title.isEmpty else { return }
        let maxOrder = tasks.filter { $0.bucketKey == bucket }.map(\.sortOrder).max() ?? -1
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
            context.insert(DayTask(
                title: title, reward: draftReward.trimmed,
                bucketKey: bucket, sortOrder: maxOrder + 1
            ))
        }
        draftTitle = ""
        draftReward = ""
        draftFocused = true   // 连续添加,不用重新点
    }

    /// 拖拽落下:换列 + 重排序(逻辑在 BoardMove,便于自检)
    private func move(uids: [String], to bucket: String, before anchor: DayTask?) -> Bool {
        var moved = false
        for uid in uids {
            guard let task = resolve(uid) else { continue }  // 外部拖入的乱字符串,直接忽略
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                if BoardMove.apply(moving: task, to: bucket, before: anchor, all: tasks) {
                    moved = true
                }
            }
        }
        if moved {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            dragOverColumn = nil
        }
        return moved
    }

    private func toggle(_ task: DayTask) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            task.completedAt = task.isDone ? nil : .now
        }
        if task.isDone {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    private func delete(_ task: DayTask) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            context.delete(task)
        }
    }
}

// MARK: - 拖拽修饰符(快照模式下整体跳过)

private struct CardDraggable: ViewModifier {
    let uid: String
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            // 不传自定义预览:SwiftUI 会自动拿卡片本身当拖拽影像
            content.draggable(uid)
        } else {
            content
        }
    }
}

private struct CardDropTarget: ViewModifier {
    let enabled: Bool
    let onDrop: ([String]) -> Bool
    let onTarget: (Bool) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: String.self) { uids, _ in
                onDrop(uids)
            } isTargeted: { over in
                onTarget(over)
            }
        } else {
            content
        }
    }
}

// MARK: - 看板卡片

struct TaskCard: View {
    let task: DayTask
    var isCompact: Bool = false
    var onToggle: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(task.isDone ? .clear : .white.opacity(hovering ? 0.5 : 0.28), lineWidth: 1.4)
                    if task.isDone {
                        Circle().fill(Theme.accentGradient)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, value: task.isDone)
                    }
                }
                .frame(width: 17, height: 17)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(task.isDone ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(task.isDone, color: Theme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(task.title)   // 窄列里被截断时,悬停看全文
                if !task.reward.isEmpty {
                    RewardChip(text: task.reward)
                }
            }
            // 优先把宽度给文字,别让奖励标签被挤成 "Ram…"
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Image(systemName: "trash")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 10)
                .opacity(hovering ? 1 : 0)
                .onTapGesture(perform: onDelete)
                .help("Delete")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(task.isDone ? 0.035 : 0.075),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.white.opacity(hovering ? 0.22 : 0.10), lineWidth: 1)
        )
        .opacity(task.isDone ? 0.72 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(task.isDone ? "Mark as Not Done" : "Mark as Done", action: onToggle)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

struct MiniButtonStyle: ButtonStyle {
    var filled: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(filled ? .white : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                if filled {
                    Capsule().fill(Theme.accentGradient)
                } else {
                    Capsule().fill(.white.opacity(0.07))
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
