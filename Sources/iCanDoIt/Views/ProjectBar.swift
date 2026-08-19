import UniformTypeIdentifiers
import SwiftUI
import SwiftData

/// 板切换条:All + 每个板一个胶囊。右键可改名/删除。
struct ProjectBar: View {
    @Environment(\.modelContext) private var context

    let projects: [Project]
    let tasks: [DayTask]
    @Binding var selected: String?     // nil = All
    /// 正在被拖的卡片 uid(由 RootView 持有)
    @Binding var draggingUID: String?
    /// 拖拽落到板胶囊上 = 把任务移到那个板
    let resolve: (String) -> DayTask?

    @State private var editing: Project?
    @State private var creating = false
    @State private var dropTarget: String?

    var body: some View {
        HStack(spacing: 7) {
            chip(
                id: nil, emoji: "🗂", name: "All",
                open: tasks.filter { !$0.isDone }.count
            )

            ForEach(projects) { p in
                chip(
                    id: p.uid, emoji: p.emoji, name: p.name,
                    open: tasks.filter { $0.projectUID == p.uid && !$0.isDone }.count
                )
                .contextMenu {
                    Button("Rename…") { editing = p }
                    if projects.count > 1 {
                        Button("Delete Board", role: .destructive) { delete(p) }
                    }
                }
            }

            Button { creating = true } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(MiniIconStyle())
            .help("New board")

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $creating) {
            ProjectSheet(title: "New Board") { name, emoji in
                let maxOrder = projects.map(\.sortOrder).max() ?? -1
                let p = Project(name: name, emoji: emoji, sortOrder: maxOrder + 1)
                context.insert(p)
                selected = p.uid
            }
        }
        .sheet(item: $editing) { p in
            ProjectSheet(title: "Rename Board", name: p.name, emoji: p.emoji) { name, emoji in
                p.name = name
                p.emoji = emoji
            }
        }
    }

    private func chip(id: String?, emoji: String, name: String, open: Int) -> some View {
        let active = selected == id
        let isOver = id != nil && dropTarget == id
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selected = id }
        } label: {
            HStack(spacing: 5) {
                Text(emoji).font(.system(size: 11))
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                if open > 0 {
                    Text("\(open)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(active ? .white : Theme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(.white.opacity(active ? 0.22 : 0.09), in: Capsule())
                }
            }
            .foregroundStyle(active ? .white : Theme.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                if active {
                    Capsule().fill(Theme.accentGradient)
                        .shadow(color: Theme.accentA.opacity(0.4), radius: 7, y: 2)
                } else {
                    Capsule().fill(.white.opacity(isOver ? 0.16 : 0.05))
                }
            }
            .overlay(
                Capsule().strokeBorder(
                    isOver ? Theme.mint.opacity(0.9) : .white.opacity(active ? 0 : 0.09),
                    lineWidth: isOver ? 1.5 : 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(ProjectDropTarget(
            enabled: id != nil && !Snapshot.offscreen,
            onDrop: { moveToProject(projectUID: id) },
            onTarget: { over in dropTarget = over ? id : nil }
        ))
        .help(id == nil ? "Everything across boards" : "Drag a card here to move it to \(name)")
    }

    private func moveToProject(projectUID: String?) -> Bool {
        guard let projectUID, let uid = draggingUID, let task = resolve(uid),
              task.projectUID != projectUID else { return false }
        withAnimation(.easeOut(duration: 0.2)) { task.projectUID = projectUID }
        draggingUID = nil
        dropTarget = nil
        return true
    }

    private func delete(_ p: Project) {
        // 板里的任务不跟着删,挪到第一个板,避免误伤
        let fallback = projects.first { $0.uid != p.uid }
        for t in tasks where t.projectUID == p.uid {
            t.projectUID = fallback?.uid ?? ""
        }
        if selected == p.uid { selected = nil }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            context.delete(p)
        }
    }
}

private struct ProjectDropTarget: ViewModifier {
    let enabled: Bool
    let onDrop: () -> Bool
    let onTarget: (Bool) -> Void

    func body(content: Content) -> some View {
        if enabled {
            // 载荷用不上(要拖的是谁由 draggingUID 记着),只关心落在哪个胶囊上
            content.onDrop(
                of: [.plainText, .utf8PlainText],
                isTargeted: Binding(get: { false }, set: { onTarget($0) })
            ) { _ in onDrop() }
        } else {
            content
        }
    }
}

// MARK: - 新建 / 改名

private struct ProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var onSave: (String, String) -> Void

    @State private var name: String
    @State private var emoji: String
    @FocusState private var focused: Bool

    init(title: String, name: String = "", emoji: String = "🎯",
         onSave: @escaping (String, String) -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: name)
        _emoji = State(initialValue: emoji)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 10) {
                Text(emoji).font(.system(size: 18))
                TextField("Board name (e.g. Job hunt)", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($focused)
                    .onSubmit(save)
            }
            .padding(12)
            .glassCard(cornerRadius: 12)

            // 图标选一个
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                ForEach(Project.emojiPalette, id: \.self) { e in
                    Button { emoji = e } label: {
                        Text(e)
                            .font(.system(size: 17))
                            .frame(width: 34, height: 34)
                            .background(
                                Circle().fill(emoji == e
                                              ? Theme.accentA.opacity(0.35) : .white.opacity(0.05))
                            )
                            .overlay(
                                Circle().strokeBorder(
                                    emoji == e ? Theme.accentA : .white.opacity(0.08),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmed.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(26)
        .frame(width: 380)
        .background(Theme.bgTop)
        .task {
            try? await Task.sleep(for: .milliseconds(200))
            focused = true
        }
    }

    private func save() {
        let n = name.trimmed
        guard !n.isEmpty else { return }
        onSave(n, emoji)
        dismiss()
    }
}

extension Project: Identifiable {}
