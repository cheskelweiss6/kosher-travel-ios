import SwiftUI

/// The city's Travel Experience page (App.tsx activeCitySubCategory 'experience'). The website lists its older
/// trip articles here, which live only in a browser's own storage (the built-in list is empty), so on a phone the
/// page shows the website's empty state with Share Your Trip, which opens the story composer for this city.
struct CityExperienceView: View {
    let page: CityPage
    @State private var compose: WebRoute?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "suitcase.rolling").font(.title3).foregroundStyle(Color.navy)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Travel Experience in \(page.name)").font(.subheadline.weight(.black)).foregroundStyle(Color.navy)
                        Text("Travel stories, personal highlights, and community experiences in \(page.name).")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
                    }
                    Spacer(minLength: 8)
                    shareButton
                }
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) { Divider().overlay(Color.hairline) }
                VStack(spacing: 12) {
                    Text("No traveler experiences yet in \(page.name) — share yours!")
                        .font(.footnote.weight(.bold)).foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    shareButton
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .hairline(radius: 16)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Color.white)
        .fullScreenCover(item: $compose) { r in
            NavigationStack { WebScreen(route: r, fullScreen: true) }
        }
    }

    private var shareButton: some View {
        Button {
            compose = .compose(city: page.name, region: page.area.isEmpty ? nil : page.area)
        } label: {
            Label("Share Your Trip", systemImage: "square.and.pencil")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 14).frame(minHeight: 36)
                .foregroundStyle(.white)
                .background(Color.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
