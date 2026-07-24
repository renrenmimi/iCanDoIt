import SwiftUI

struct MorningRitualView: View {
    var onStart: ([TaskDraft]) -> Void

    @State private var drafts: [TaskDraft] = []
    @State private var title = ""
    @State private var reward = ""
    @FocusState private var focus: Field?

    enum Field { case title, reward }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 44)

            VStack(spacing: 10) {
                Text(DateInfo.todayString)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(DateInfo.greeting) 👋")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .legibilityShadow()
                Text("What do you want to get done today?")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accentGradient)
                    .shadow(color: Theme.accentA.opacity(0.55), radius: 18, y: 2)
            }
            .padding(.bottom, 28)

            VStack(spacing: 12) {
                if !drafts.isEmpty {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(Array(drafts.enumerated()), id: \.element.id) { idx, draft in
                                draftRow(index: idx, draft: draft)
                            }
                        }
                        .padding(2)
                    }
                    .frame(maxHeight: 216)
                }

                inputCard

                Button {
                    commitPendingInput()
                    guard !drafts.isEmpty else { return }
                    onStart(drafts)
                } label: {
                    HStack(spacing: 8) {
                        Text("Start the Day")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(drafts.isEmpty && trimmed(title).isEmpty)
                .padding(.top, 10)
            }
            .frame(width: 520)

            Spacer(minLength: 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            focus = .title
        }
    }

    private var inputCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Write down one thing to do today…", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($focus, equals: .title)
                    .onSubmit {
                        if !trimmed(title).isEmpty { focus = .reward }
                    }
            }
            Divider().overlay(.white.opacity(0.08))
            HStack(spacing: 10) {
                Image(systemName: "gift")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accentB.opacity(0.85))
                TextField("Reward yourself with… (optional)", text: $reward)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($focus, equals: .reward)
                    .onSubmit(addDraft)
                Button(action: addDraft) {
                    Image(systemName: "plus")
                }
                .buttonStyle(IconButtonStyle())
                .disabled(trimmed(title).isEmpty)
                .help("Add to today's list")
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }

    private func draftRow(index: Int, draft: TaskDraft) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 22, height: 22)
                .background(Theme.accentGradient, in: Circle())
            Text(draft.title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if !draft.reward.isEmpty {
                RewardChip(text: draft.reward)
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    drafts.removeAll { $0.id == draft.id }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 12)
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    private func addDraft() {
        let t = trimmed(title)
        guard !t.isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            drafts.append(TaskDraft(title: t, reward: trimmed(reward)))
        }
        title = ""
        reward = ""
        focus = .title
    }

    private func commitPendingInput() {
        let t = trimmed(title)
        guard !t.isEmpty else { return }
        drafts.append(TaskDraft(title: t, reward: trimmed(reward)))
        title = ""
        reward = ""
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
