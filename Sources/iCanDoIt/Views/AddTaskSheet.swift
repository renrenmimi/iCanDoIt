import SwiftUI

struct AddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (String, String) -> Void

    @State private var title = ""
    @State private var reward = ""
    @FocusState private var titleFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("New Task")
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
            }
            .padding(12)
            .glassCard(cornerRadius: 12)

            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onAdd(trimmedTitle, reward.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(trimmedTitle.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(26)
        .frame(width: 420)
        .background(Theme.bgTop)
        .task {
            try? await Task.sleep(for: .milliseconds(200))
            titleFocused = true
        }
    }
}
