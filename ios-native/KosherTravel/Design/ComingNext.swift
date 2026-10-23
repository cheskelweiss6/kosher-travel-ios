import SwiftUI

/// A tab that is rebuilt in a later step. It says so plainly instead of showing a half-working screen.
struct ComingNext: View {
    let title: String
    let systemImage: String
    let detail: String
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(detail)
            }
            .foregroundStyle(Color.navy)
            .navigationTitle(title)
        }
    }
}
