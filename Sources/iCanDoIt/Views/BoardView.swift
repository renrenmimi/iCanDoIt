import AppKit
import SwiftUI
import SwiftData

/// Trello 式看板:横向若干列,卡片可在列间拖动
struct BoardView: View {
    @Environment(\.modelContext) private var context

    let scope: BoardScope
    let columns: [BoardColumn]
    let tasks: [DayTask]
    /// 新卡片归属的板;All 模式下为第一个板
    let activeProjectUID: String
    /// All 模式下在卡片上显示板的标记
    let projectBadges: [String: String]
    /// 正在被拖的卡片 uid(由 onDrag 在拖拽开始时记下)
    @Binding var draggingUID: String?
    /// 拖拽落下时由父层解析 uid → 任务
    let resolve: (String) -> DayTask?

    @State private var dragOverColumn: String?
    /// 当前拖拽的落点(哪一列、第几个),用来画插入指示线
    @State private var slot: DropSlot?
    /// 仅供快照自检:强制显示某个落点,好验证指示线画得对不对
    var debugSlot: DropSlot? = nil
    @State private var editing: DayTask?
    @State private var addingTo: String?
    @State private var draftTitle = ""
    @State private var draftReward = ""
    @State private var draftUrgent = false
    @FocusState private var draftFocused: Bool
    /// 每张卡片在所属列坐标系里的纵向中点,用来算落点该插到第几个
    @State private var cardMidY: [String: CGFloat] = [:]
    @State private var watchdog = DragWatchdog()

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
        .sheet(item: $editing) { task in
            TaskEditorSheet(task: task) { title, reward, urgent in
                task.title = title
                task.reward = reward
                task.isUrgent = urgent
            } onDelete: {
                delete(task)
            }
        }
    }

    // MARK: - 单列

    private func columnView(_ column: BoardColumn) -> some View {
        let items = cards(in: column.id)
        let doneCount = items.filter(\.isDone).count
        let activeSlot = slot ?? debugSlot
        let isOver = (dragOverColumn ?? debugSlot?.column) == column.id

        return VStack(alignment: .leading, spacing: 10) {
            columnHeader(column, total: items.count, done: doneCount)

            MaybeScroll(axis: .vertical) {
                VStack(spacing: 7) {
                    ForEach(Array(items.enumerated()), id: \.element.uid) { idx, task in
                        // 指示线插在这张卡之前
                        if activeSlot == DropSlot(column: column.id, index: idx) {
                            InsertionLine()
                        }
                        TaskCard(
                            task: task, isCompact: true,
                            projectBadge: projectBadges[task.projectUID],
                            onToggle: { toggle(task) },
                            onDelete: { delete(task) },
                            onEdit: { editing = task }
                        )
                        .modifier(CardDraggable(uid: task.uid, enabled: interactive) {
                            draggingUID = task.uid
                        })
                        // 记录每张卡的纵向位置,供落点计算用
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .named(column.id)).midY
                        } action: { midY in
                            cardMidY[task.uid] = midY
                        }
                    }
                    // 落在最后一张之后
                    if activeSlot == DropSlot(column: column.id, index: items.count) {
                        InsertionLine()
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
        // 整列只有这一个放置目标(嵌套目标会互相抢事件,造成落下时的卡顿)
        .coordinateSpace(.named(column.id))
        .modifier(SlotDropModifier(
            enabled: interactive,
            delegate: SlotDropDelegate(
                column: column.id,
                slotAt: { point in insertIndex(in: items, dropY: point.y) },
                onHover: { s in
                    withAnimation(.easeOut(duration: 0.12)) {
                        slot = s
                        dragOverColumn = s?.column
                    }
                    // 拖拽一旦结束(含被取消),指示线自己消失
                    if s != nil {
                        watchdog.begin { clearDragState() }
                    }
                },
                onExit: { col in
                    // 只有落点还属于这一列时才清,避免跨列时清掉新列的落点
                    if slot?.column == col { clearDragState() }
                },
                onPerform: { index in
                    move(to: column.id, displayIndex: index, in: items)
                }
            )
        ))
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
            draftUrgent = false
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
                // 加急开关
                Button {
                    draftUrgent.toggle()
                } label: {
                    Image(systemName: draftUrgent
                          ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(draftUrgent ? Theme.urgent : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help(draftUrgent ? "Urgent — click to clear" : "Mark as urgent")
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
            let t = DayTask(
                title: title, reward: draftReward.trimmed,
                bucketKey: bucket, sortOrder: maxOrder + 1,
                projectUID: activeProjectUID
            )
            t.isUrgent = draftUrgent
            context.insert(t)
        }
        draftTitle = ""
        draftReward = ""
        draftFocused = true   // 连续添加,不用重新点
    }

    /// 收起指示线与列高亮
    private func clearDragState() {
        watchdog.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            slot = nil
            dragOverColumn = nil
        }
    }

    /// 鼠标落点在第几张卡片之间:落点上方的卡片数就是插入位置
    private func insertIndex(in items: [DayTask], dropY: CGFloat) -> Int {
        items.filter { (cardMidY[$0.uid] ?? .greatestFiniteMagnitude) < dropY }.count
    }

    /// 落下:把「显示位置」换算成 BoardMove 需要的「兄弟节点位置」
    private func move(to bucket: String, displayIndex: Int, in items: [DayTask]) -> Bool {
        guard let uid = draggingUID, let task = resolve(uid) else { return false }

        // 被拖的卡自己还在列表里占了个位;它原本在落点之上时,目标序号要减一
        var target = displayIndex
        if let current = items.firstIndex(where: { $0.uid == uid }), current < displayIndex {
            target -= 1
        }

        var moved = false
        // 动画要短:落下时会触发整块看板重绘,慢弹簧会被看成"卡了一下"
        withAnimation(.easeOut(duration: 0.18)) {
            moved = BoardMove.apply(moving: task, to: bucket, at: target, all: tasks)
        }
        if moved {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
        draggingUID = nil
        clearDragState()
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

/// 用 .onDrag 而不是 .draggable:前者的闭包在拖拽开始时执行,
/// 正好用来记下"正在拖谁"——落下时算插入位置需要它。
struct CardDraggable: ViewModifier {
    let uid: String
    let enabled: Bool
    let onStart: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onDrag {
                onStart()
                return NSItemProvider(object: uid as NSString)
            }
        } else {
            content
        }
    }
}

struct SlotDropModifier: ViewModifier {
    let enabled: Bool
    let delegate: SlotDropDelegate

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [.plainText, .utf8PlainText], delegate: delegate)
        } else {
            content
        }
    }
}

// MARK: - 看板卡片

struct TaskCard: View {
    let task: DayTask
    var isCompact: Bool = false
    /// All 模式下显示这张卡属于哪个板(单板模式传 nil)
    var projectBadge: String?
    var onToggle: () -> Void
    var onDelete: () -> Void
    var onEdit: (() -> Void)?

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
                if let projectBadge {
                    Text(projectBadge)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
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

            // 悬停时露出的操作按钮(可见入口,不依赖双击)
            VStack(spacing: 7) {
                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit this card")
                }
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            .frame(width: 12)
            // 平时淡显、悬停变亮:入口始终可见,不用猜
            .opacity(hovering ? 1 : 0.4)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(task.isDone ? 0.035 : 0.075),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    task.isUrgent && !task.isDone
                        ? Theme.urgent.opacity(hovering ? 0.85 : 0.6)
                        : .white.opacity(hovering ? 0.22 : 0.10),
                    lineWidth: 1
                )
        )
        // 加急:左侧一道竖条,一眼能认出来
        .overlay(alignment: .leading) {
            if task.isUrgent {
                Capsule()
                    .fill(Theme.urgent.opacity(task.isDone ? 0.35 : 1))
                    .frame(width: 3)
                    .padding(.vertical, 7)
                    .padding(.leading, 2)
            }
        }
        .opacity(task.isDone ? 0.72 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        // 用 simultaneousGesture:普通 onTapGesture 会和 .draggable 抢事件
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { onEdit?() }
        )
        .contextMenu {
            if let onEdit {
                Button("Edit…", action: onEdit)
            }
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
