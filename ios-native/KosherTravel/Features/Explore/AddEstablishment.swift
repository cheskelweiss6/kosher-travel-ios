import SwiftUI

/// "Add Kosher Establishment for {city}" (App.tsx contribution form + handleAddPlace). Opened from the Chabad page's
/// "Confirm & Post Chabad Restaurant", prefilled like the website. Posts the same body to the same /api/places.
struct AddEstablishmentSheet: View {
    let cityName: String
    let country: String
    var preset: Preset

    struct Preset {
        var name = ""
        var category = "restaurant"
        var subCategory = ""
        var address = ""
        var kashrus = ""
        var phone = ""
        var website = ""
        var description = ""
    }

    @Environment(\.dismiss) private var dismiss
    @State private var p = Preset()
    @State private var loaded = false
    @State private var success = false
    @State private var sending = false
    @State private var missing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Contribute a verified kosher dining spot or Chabad service to help other travelers.")
                        .font(.footnote).foregroundStyle(Color.textSecondary)
                }
                Section("Establishment Name *") { TextField("e.g. Shalva Kosher Cafe", text: $p.name) }
                Section("Category *") {
                    Picker("Category", selection: $p.category) {
                        Text("Kosher Restaurant").tag("restaurant")
                        Text("Chabad House").tag("chabad")
                        Text("Kosher Grocery / Supermarket").tag("grocery")
                    }
                    .labelsHidden()
                }
                Section("Supervision / Kashrus *") { TextField("e.g. Badatz, OU, Chabad", text: $p.kashrus) }
                Section("Sub-Category (Cuisine)") { TextField("e.g. Dairy / Pizzeria", text: $p.subCategory) }
                Section("Street Address *") { TextField("e.g. 10 Chabad Lane, Ocean Drive", text: $p.address) }
                if success {
                    Section {
                        Label("Establishment added successfully! indexed & saved.", systemImage: "checkmark.circle")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Color.navy)
                    }
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        Text("Submit Establishment to Database").font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(sending)
                }
            }
            .tint(Color.navy)
            .navigationTitle("Add Kosher Establishment for \(cityName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .alert("Please fill out Name, Address, and Kashrus fields!", isPresented: $missing) { Button("OK", role: .cancel) {} }
            .onAppear { if !loaded { p = preset; loaded = true } }
        }
    }

    @MainActor
    private func submit() async {
        if p.name.isEmpty || p.address.isEmpty || p.kashrus.isEmpty { missing = true; return }
        sending = true
        defer { sending = false }
        let body: [String: Any] = [
            "name": p.name, "category": p.category, "subCategory": p.subCategory, "city": cityName, "country": country,
            "address": p.address, "kashrus": p.kashrus, "phone": p.phone, "website": p.website, "description": p.description,
            "lat": 18.42, "lng": -77.10, "priceRange": "$$",  // the website's newPlace defaults, sent as is
            "isGlattMeat": false, "isCholovYisroel": false, "isPasYisroel": false,
            "shabbatMeals": false, "dailyMinyan": false, "hasBakery": false, "hasButcher": false,
        ]
        guard let url = URL(string: "https://www.yourkoshertravel.com/api/places"),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        // Website: on success it shows the line, clears the form and closes after 2 s; on failure it stays as is.
        // (Oct 23: the live site answers this POST with 404, so the website form doesn't save either.)
        guard let result = try? await URLSession.shared.data(for: req),
              let http = result.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
        success = true
        p = Preset(category: p.category, subCategory: p.subCategory)  // website keeps category and cuisine
        try? await Task.sleep(for: .seconds(2))
        dismiss()
    }
}
