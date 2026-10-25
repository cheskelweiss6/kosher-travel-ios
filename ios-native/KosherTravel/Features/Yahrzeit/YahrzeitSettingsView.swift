import SwiftUI
import UserNotifications
import UIKit

/// Settings → "Yahrzeit alerts" (the website's Settings switch, SettingsSheet.tsx YahrzeitGroup, as a native screen).
/// Same setting as the website (users/{uid}/userData/yahrzeitPrefs); the notifications are booked on this phone.
struct YahrzeitSettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.openURL) private var openURL
    @MainActor private var alerts: YahrzeitAlerts { YahrzeitAlerts.shared }
    @State private var testSent = 0

    private var denied: Bool { alerts.permission == .denied }

    var body: some View {
        Form {
            Section {
                Toggle("Yahrzeit alerts", isOn: Binding(
                    get: { alerts.prefs.on },
                    set: { v in var p = alerts.prefs; p.on = v; Task { await alerts.save(p) } }))
                    .accessibilityIdentifier("yahrzeit-switch")
            } footer: {
                Text("A notification on the day of each yahrzeit and a few days before, at 9 AM.")
            }

            if alerts.prefs.on {
                Section {
                    Picker("Which kevarim", selection: Binding(
                        get: { auth.isSignedIn ? alerts.prefs.scope : "all" },
                        set: { v in var p = alerts.prefs; p.scope = v; Task { await alerts.save(p) } })) {
                        Text("Saved kevarim").tag("saved")
                        Text("All kevarim").tag("all")
                    }
                    .disabled(!auth.isSignedIn)
                    Picker("Remind me", selection: Binding(
                        get: { alerts.prefs.daysBefore },
                        set: { v in var p = alerts.prefs; p.daysBefore = v; Task { await alerts.save(p) } })) {
                        ForEach(YahrzeitPrefs.dayChoices, id: \.self) { d in
                            Text(d == 1 ? "1 day before" : "\(d) days before").tag(d)
                        }
                    }
                } footer: {
                    Text(auth.isSignedIn
                         ? "Saved kevarim are the ones with a heart in Kivrei Tzadikim."
                         : "Sign in to get alerts only for the kevarim you save with a heart.")
                }

                Section {
                    if denied {
                        Button {
                            if let u = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(u) }
                        } label: {
                            SettingsRow(icon: "bell.slash", label: "Notifications are off for Kosher Travel", value: "Turn on", external: true)
                        }
                    } else {
                        SettingsRow(icon: "bell", label: "Booked on this phone", value: "\(alerts.booked)")
                        if let n = alerts.next {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Next alert").font(.footnote).foregroundStyle(Color.textSecondary)
                                Text(n.body).foregroundStyle(Color.navy)
                                Text(n.fire.formatted(date: .abbreviated, time: .shortened))
                                    .font(.footnote).foregroundStyle(Color.textSecondary)
                            }
                            .accessibilityIdentifier("yahrzeit-next")
                        } else if alerts.prefs.scope == "saved" && auth.isSignedIn && alerts.savedCount == 0 {
                            Text("No saved kevarim yet. Tap the heart on a kever to get its yahrzeit alerts.")
                                .font(.footnote).foregroundStyle(Color.textSecondary)
                        }
                        Button {
                            Task { await alerts.sendTest(); testSent += 1 }
                        } label: {
                            SettingsRow(icon: "paperplane", label: "Send a test alert", value: nil)
                        }
                        .accessibilityIdentifier("yahrzeit-test")
                        .sensoryFeedback(Motion.Haptic.selection, trigger: testSent)
                        if testSent > 0 {
                            FormNote(ok: true, text: "A test alert arrives in a few seconds, on this phone only.")
                        }
                    }
                } header: {
                    Text("On this phone")
                }
            }
        }
        .tint(Color.navy)
        .foregroundStyle(Color.navy)
        .scrollContentBackground(.hidden)
        .background(Color.surface)
        .navigationTitle("Yahrzeit alerts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await alerts.refresh(uid: auth.uid) }
    }
}

/// Books the yahrzeit notifications again when the app starts, comes back to the front, or the person signs in or out.
struct YahrzeitLifecycle: ViewModifier {
    @Environment(AuthStore.self) private var auth
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .task(id: "\(auth.ready)|\(auth.uid ?? "")") {
                guard auth.ready else { return }
                await YahrzeitAlerts.shared.refresh(uid: auth.uid)
            }
            .onChange(of: phase) { _, now in
                guard now == .active, auth.ready else { return }
                Task { await YahrzeitAlerts.shared.refresh(uid: auth.uid) }
            }
    }
}
