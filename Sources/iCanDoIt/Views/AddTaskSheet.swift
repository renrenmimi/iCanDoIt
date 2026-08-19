import SwiftUI

/// 新建 / 编辑任务。两种模式共用一套表单。
struct TaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isEditing: Bool
    var onSave: (String, String, Bool) -> Void
    var onDelete: (() -> Void)?

    @State private var title: String
    @State private var reward: String
    @State private var urgent: Bool
    @FocusState private var titleFocused: Bool

    /// 新建
    init(onAdd: @escaping (String, String, Bool) -> Void) {
        isEditing = false
        onSave = onAdd
        onDelete = nil
        _title = State(initialValue: "")
        _reward = State(initialValue: "")
        _urgent = State(initialValue: false)
    }

    /// 编辑已有任务
    init(task: DayTask,
         onSave: @escaping (String, String, Bool) -> Void,
         onDelete: @escaping () -> Void) {
        isEditing = true
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: task.title)
        _reward = State(initialValue: task.reward)
        _urgent = State(initialValue: task.isUrgent)
    }

    private var trimmedTitle: String { title.trimmed }

    var body: some View {
        VStack(spacing: 16) {
            Text(isEditing ? "Edit Task" : "New Task")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Something to get done…", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($titleFocused)
                    .onSubmit(save)
            }
            .padding(12)
            .glassCard(cornerRadius: 12)

            HStack(spacing: 10) {
                Image(systemName: "gift")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accentB.opacity(0.85))
                TextField("Reward yourself with… (optional)", text: $reward)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .onSubmit(save)
            }
            .padding(12)
            .glassCard(cornerRadius: 12)

            urgentToggle

            HStack(spacing: 10) {
                if isEditing, let onDelete {
                    Button {
                        onDelete()
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Delete this task")
                }
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(trimmedTitle.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(26)
        .frame(width: 420)
        .background(Theme.bgTop)
        .task {
            try? await Task.sleep(for: .milliseconds(200))
            titleFocused = true
        }
    }

    private var urgentToggle: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { urgent.toggle() }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: urgent ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(urgent ? Theme.urgent : Theme.textSecondary)
                    .symbolEffect(.bounce, value: urgent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Urgent")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Marks the card so it stands out")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                // 小开关
                Capsule()
                    .fill(urgent ? Theme.urgent : .white.opacity(0.14))
                    .frame(width: 34, height: 20)
                    .overlay(alignment: urgent ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 16, height: 16)
                            .padding(2)
                    }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(urgent ? Theme.urgent.opacity(0.10) : .white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(urgent ? Theme.urgent.opacity(0.45) : .white.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let t = trimmedTitle
        guard !t.isEmpty else { return }
        onSave(t, reward.trimmed, urgent)
        dismiss()
    }
}
