import SwiftUI

/// The chat list, newest first (web: the planner drawer). Tap to reopen a chat exactly as it was; swipe to delete.
struct PlannerHistoryView: View {
    let store: PlannerStore
    let signedIn: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    ContentUnavailableView {
                        Label("No chats yet", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Your conversations with the AI Planner show up here.")
                    }
                    .foregroundStyle(Color.navy)
                } else {
                    List {
                        Section {
                            ForEach(store.sessions) { s in
                                Button {
                                    store.open(s)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(s.title.isEmpty ? "New chat" : s.title)
                                                .font(.body)
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { store.delete(s) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } footer: {
                            Text(signedIn
                                 ? "Your chats are saved to your account and open on the website too."
                                 : "Chats are saved on this iPhone. Sign in to keep them on all your devices.")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
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
        }
        .presentationDetents([.medium, .large])
    }

    static func when(_ d: Date) -> String {
        guard d != .distantPast else { return "" }
        if Calendar.current.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}
