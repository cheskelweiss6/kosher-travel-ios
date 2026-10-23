import Foundation
import Observation
import FirebaseFirestore

/// Saved places (the website's bucket list): destination ids with the time each was saved. On this phone, and in
/// users/{uid}/userData/preferences { bucketList, bucketListTimestamps, updatedAt } when signed in, exactly what
/// App.tsx handleToggleBucketList / saveUserDataDocToFirestore write, so My Travel on the web shows the same list.
@Observable
final class BucketList {
    static let shared = BucketList()

    private(set) var ids: [String] = []
    private(set) var timestamps: [String: Double] = [:]
    @ObservationIgnored private var uid: String?

    private func key(_ base: String) -> String { uid.map { "\(base)_\($0)" } ?? base }

    func contains(_ destId: String) -> Bool { ids.contains(destId) }

    /// Called when the signed-in person changes: local copy first, then the account's copy when it has one.
    func bind(uid newUid: String?) async {
        guard newUid != uid || ids.isEmpty else { return }
        uid = newUid
        let d = UserDefaults.standard
        ids = d.stringArray(forKey: key("kosherway_bucketlist")) ?? []
        timestamps = (d.dictionary(forKey: key("kosherway_bucketlist_timestamps")) as? [String: Double]) ?? [:]
        guard let newUid, FirebaseBoot.isConfigured else { return }
        let ref = Firestore.firestore().collection("users").document(newUid).collection("userData").document("preferences")
        guard let snap = try? await ref.getDocument(), let data = snap.data(), uid == newUid else { return }
        if let list = data["bucketList"] as? [String] {
            ids = list
            var ts: [String: Double] = [:]
            for (k, v) in (data["bucketListTimestamps"] as? [String: Any]) ?? [:] {
                if let n = v as? NSNumber { ts[k] = n.doubleValue }
            }
            timestamps = ts
            saveLocal()
        }
    }

    func toggle(_ destId: String) {
        if let i = ids.firstIndex(of: destId) {
            ids.remove(at: i)
            timestamps[destId] = nil
        } else {
            ids.append(destId)
            timestamps[destId] = (Date().timeIntervalSince1970 * 1000).rounded()
        }
        saveLocal()
        guard let uid, FirebaseBoot.isConfigured else { return }
        let list = ids, ts = timestamps
        Task {
            try? await Firestore.firestore().collection("users").document(uid).collection("userData").document("preferences")
                .setData(["bucketList": list, "bucketListTimestamps": ts, "updatedAt": FieldValue.serverTimestamp()], merge: true)
        }
    }

    private func saveLocal() {
        let d = UserDefaults.standard
        d.set(ids, forKey: key("kosherway_bucketlist"))
        d.set(timestamps, forKey: key("kosherway_bucketlist_timestamps"))
    }
}
