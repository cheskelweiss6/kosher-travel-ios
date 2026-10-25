import SwiftUI

/// The chat list, newest first, grouped by day (web: the planner drawer). Tap to reopen a chat exactly as it was.
/// Delete: swipe left, the ••• menu, touch and hold, or Edit (web: swipe → Delete, ••• → Delete chat, then
/// "Delete this chat?").
struct PlannerHistoryView: View {
    let store: PlannerStore
    let signedIn: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: ChatSession?
    @State private var deleted = 0

    private struct DayGroup: Identifiable {
        var label: String
        var items: [ChatSession]
        var id: String { label }
    }

    private var groups: [DayGroup] {
        var out: [DayGroup] = []
        for s in store.sessions {
            let label = Self.dayLabel(s.sortDate)
            if let i = out.firstIndex(where: { $0.label == label }) { out[i].items.append(s) } else { out.append(DayGroup(label: label, items: [s])) }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    ContentUnavailableView {
                        Label("No chats yet", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Your past chats will show here.")
                    }
                    .foregroundStyle(Color.navy)
                } else {
                    List {
                        ForEach(groups) { g in
                            Section(g.label) {
                                ForEach(g.items) { s in row(s) }
                                    .onDelete { offsets in
                                        // every delete asks first (Cheskel, Oct 23 9:20)
                                        if let i = offsets.first, g.items.indices.contains(i) { pendingDelete = g.items[i] }
                                    }
                            }
                        }
                        Section {
                            EmptyView()
                        } footer: {
                            Text("Every chat starts fresh. The planner only reads the chat you are in and does not learn about you."
                                 + (signedIn ? " Your chats are kept in your account; delete any chat from the chat list."
                                             : " Your chats are kept on this phone; delete any chat from the chat list."))
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if !store.sessions.isEmpty {
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.newChat()
                        dismiss()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New chat")
                }
            }
            .confirmationDialog("Delete this chat?", isPresented: Binding(get: { pendingDelete != nil },
                                                                          set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { s in
                Button("Delete", role: .destructive) {
                    store.delete(s)
                    deleted += 1
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { _ in
                Text("This conversation will be permanently deleted.")
            }
            .sensoryFeedback(Motion.Haptic.success, trigger: deleted)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ s: ChatSession) -> some View {
        HStack(spacing: 8) {
            Button {
                store.open(s)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title.isEmpty ? "New chat" : s.title)
                            .font(.body.weight(s.id == store.currentId ? .semibold : .regular))
                            .foregroundStyle(Color.navy)
                            .lineLimit(2)
                        Text(Self.when(s.sortDate))
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if s.id == store.currentId {
                        Image(systemName: "checkmark").foregroundStyle(Color.navy)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(role: .destructive) { pendingDelete = s } label: {
                    Label("Delete chat", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options for chat: \(s.title.isEmpty ? "New chat" : s.title)")
        }
        .contextMenu {
            Button(role: .destructive) { pendingDelete = s } label: {
                Label("Delete chat", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { pendingDelete = s } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Web: dayLabel (Today, Yesterday, Previous 7 days, Previous 30 days, Earlier).
    static func dayLabel(_ d: Date) -> String {
        guard d != .distantPast else { return "Earlier" }
        let cal = Calendar.current
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
        if diff <= 0 { return "Today" }
        if diff == 1 { return "Yesterday" }
        if diff < 7 { return "Previous 7 days" }
        if diff < 31 { return "Previous 30 days" }
        return "Earlier"
    }

    static func when(_ d: Date) -> String {
        guard d != .distantPast else { return "" }
        if Calendar.current.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}
