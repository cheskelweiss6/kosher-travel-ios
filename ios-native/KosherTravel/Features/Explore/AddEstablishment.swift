import SwiftUI
import FirebaseFirestore

/// "Add Kosher Establishment for {city}" (App.tsx contribution form + handleAddPlace). Opened from the Chabad page's
/// "Confirm & Post Chabad Restaurant", prefilled like the website.
/// Oct 23 2026 (Cheskel approved gap G10): the place goes to the admin's review queue (Admin > Review, "Places people
/// sent"), the same document the website writes (src/components/placeSubmit.ts):
///   places/{auto} { name, category, subCategory, cityName, cityId, country, address, hechsher, phone, website,
///                   description, status "pending", source "submission", addedBy, addedByName, createdAt }
/// It used to POST to /api/places, which answers 404, so nothing was saved. Signed in only (the rules refuse others).
struct AddEstablishmentSheet: View {
    let cityName: String
    let country: String
    var cityId: String = ""
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
    @Environment(AuthStore.self) private var auth
    @State private var failed = false
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
                        Label("Sent for review. It shows in the app once the admin approves it.", systemImage: "checkmark.circle")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Color.navy)
                    }
                }
                if failed {
                    Section {
                        Label("Couldn't send it right now. Check your connection and try again.", systemImage: "exclamationmark.circle")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Color.alert)
                    }
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        Text(sending ? "Sending…" : "Send for review").font(.subheadline.weight(.bold))
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
        guard let uid = auth.uid else {
            ShellRouter.shared.requireSignIn("Sign in to send a place. It goes to the admin for review.")
            return
        }
        guard FirebaseBoot.isConfigured else { failed = true; return }
        sending = true
        failed = false
        defer { sending = false }
        func cut(_ v: String, _ n: Int) -> String { String(v.trimmingCharacters(in: .whitespacesAndNewlines).prefix(n)) }
        let category = ["restaurant", "chabad", "grocery"].contains(p.category) ? p.category : "restaurant"
        let data: [String: Any] = [
            "name": cut(p.name, 120), "category": category, "subCategory": cut(p.subCategory, 80),
            "cityName": cut(cityName, 80), "cityId": cut(cityId, 80), "country": cut(country, 80),
            "address": cut(p.address, 300), "hechsher": cut(p.kashrus, 200), "phone": cut(p.phone, 40),
            "website": cut(p.website, 300), "description": cut(p.description, 1000),
            "status": "pending", "source": "submission", "addedBy": uid,
            "addedByName": cut(auth.displayName.isEmpty ? "Traveler" : auth.displayName, 80),
            "createdAt": FieldValue.serverTimestamp(),
        ]
        do {
            _ = try await Firestore.firestore().collection("places").addDocument(data: data)
        } catch {
            print("[KT] place not sent: \(error)")
            failed = true
            return
        }
        success = true
        p = Preset(category: p.category, subCategory: p.subCategory)  // website keeps category and cuisine
        try? await Task.sleep(for: .seconds(3))
        dismiss()
    }
}
