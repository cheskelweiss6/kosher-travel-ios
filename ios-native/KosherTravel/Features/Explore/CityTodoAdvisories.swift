import SwiftUI

/// The website's "Essential Travel & Logistics Advisories" box (components/DeepExperiencesView.tsx, after the
/// category chips): a slate card with a compass header and the destination's travelTips in two columns.
struct CityTodoAdvisories: View {
    let tips: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Essential Travel & Logistics Advisories").textCase(.uppercase)
            } icon: {
                Image(systemName: "safari")
            }
            .font(.caption.weight(.bold)).tracking(0.6)
            .foregroundStyle(Color.navy)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .topLeading),
                                GridItem(.flexible(), spacing: 8, alignment: .topLeading)],
                      alignment: .leading, spacing: 8) {
                ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\u{2022}").font(.system(size: 11.5, weight: .bold))
                        Text(tip).font(.system(size: 11.5)).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Color.navy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
    }
}
