//
//  AppState.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AppState: ObservableObject {
    @Published var halls: [DiningHall] = SampleData.halls
    @Published var selectedHall: DiningHall? = nil
    @Published var selectedItem: MenuItem? = nil

    // Firebase auth user
    @Published var firebaseUser: User? = Auth.auth().currentUser
    @Published var isVerified: Bool = Auth.auth().currentUser?.isEmailVerified ?? false

    private var authHandle: AuthStateDidChangeListenerHandle? = nil

    init() {
        let list = halls.map { "\($0.name): \($0.verifiedCount)" }.joined(separator: ", ")
        print("[AppState] init - loaded halls verified counts -> \(list)")

        if halls.allSatisfy({ $0.verifiedCount == 0 }) {
            let proto: [String: Int] = ["1": 142, "2": 89, "3": 5]
            for idx in halls.indices {
                if let v = proto[halls[idx].id] {
                    halls[idx].verifiedCount = v
                }
            }
            let updated = halls.map { "\($0.name): \($0.verifiedCount)" }.joined(separator: ", ")
            print("[AppState] init - applied prototype verified counts -> \(updated)")
        }

        // Observe Firebase auth state
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let verified = user?.isEmailVerified ?? false
            Task { @MainActor in
                self?.firebaseUser = user
                self?.isVerified = verified
                print("[AppState] auth state changed - user: \(user?.uid ?? "none"), verified: \(verified)")
            }
        }
    }

    deinit {
        if let h = authHandle { Auth.auth().removeStateDidChangeListener(h) }
    }

    func updateWaitTime(for hallID: String, to minutes: Int) {
        guard let idx = halls.firstIndex(where: { $0.id == hallID }) else { return }
        let newText = minutes < 2 ? "1-2 min" : "\(max(1, minutes-1))-\(minutes+1) min"
        halls[idx].waitTime = newText
        halls[idx].lastUpdated = "just now"
        halls[idx].verifiedCount += 1
        print("[AppState] updateWaitTime - \(halls[idx].name) verifiedCount -> \(halls[idx].verifiedCount)")
    }

    func updateStatus(for hallID: String, to newStatus: HallStatus) {
        guard let idx = halls.firstIndex(where: { $0.id == hallID }) else { return }
        halls[idx].status = newStatus
    }
    
    func submitRating(for itemID: String, in hallID: String, rating newRating: Int) {
        guard let hIdx = halls.firstIndex(where: { $0.id == hallID }) else { return }
        guard let iIdx = halls[hIdx].menuItems.firstIndex(where: { $0.id == itemID }) else { return }
        var item = halls[hIdx].menuItems[iIdx]
        let total = item.rating * Double(item.reviewCount) + Double(newRating)
        item.reviewCount += 1
        item.rating = total / Double(item.reviewCount)
        halls[hIdx].menuItems[iIdx] = item
        halls[hIdx].verifiedCount += 1
        print("[AppState] submitRating - \(halls[hIdx].name) verifiedCount -> \(halls[hIdx].verifiedCount)")
    }
    
    // MARK: - Authentication helpers
    func signUp(firstName: String, lastName: String, email: String, password: String, completion: @escaping (Error?) -> Void) {
        let lower = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.hasSuffix("@gatech.edu") else {
            completion(NSError(domain: "SignUp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Please use a @gatech.edu email."]))
            return
        }
        Auth.auth().createUser(withEmail: lower, password: password) { [weak self] result, error in
            if let error = error { completion(error); return }
            guard let user = result?.user else { completion(NSError(domain: "SignUp", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown user after signup"])) ; return }
            // Send verification email
            user.sendEmailVerification { sendError in
                if let sendError = sendError { completion(sendError); return }
                // create profile
                let db = Firestore.firestore()
                let data: [String: Any] = [
                    "firstName": firstName,
                    "lastName": lastName,
                    "email": lower,
                    "createdAt": Timestamp(date: Date())
                ]
                // set Auth displayName so profile initials are available immediately
                let fullName = "\(firstName) \(lastName)"
                let change = user.createProfileChangeRequest()
                change.displayName = fullName
                change.commitChanges { _ in
                    db.collection("users").document(user.uid).setData(data) { writeError in
                        if let writeError = writeError { completion(writeError); return }
                        // optionally sign out so they must verify before using app features
                        do { try Auth.auth().signOut() } catch { /* ignore */ }
                        completion(nil)
                    }
                }
             }
         }
     }

    func signIn(email: String, password: String, completion: @escaping (Error?) -> Void) {
        Auth.auth().signIn(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), password: password) { result, error in
            if let error = error { completion(error); return }
            guard let user = result?.user else { completion(NSError(domain: "Auth", code: 3, userInfo: [NSLocalizedDescriptionKey: "No user after sign-in"])) ; return }
            if !user.isEmailVerified {
                do { try Auth.auth().signOut() } catch { /* ignore */ }
                completion(NSError(domain: "Auth", code: 4, userInfo: [NSLocalizedDescriptionKey: "Please verify your @gatech.edu email before signing in."]))
                return
            }
            completion(nil)
        }
    }

    func signOut() {
        do { try Auth.auth().signOut(); firebaseUser = nil; isVerified = false } catch { print("[AppState] signOut error: \(error)") }
    }

    func resendVerification(completion: @escaping (Error?) -> Void) {
        guard let user = Auth.auth().currentUser else { completion(NSError(domain: "Auth", code: 5, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])) ; return }
        user.sendEmailVerification { error in
            completion(error)
        }
    }

    func refreshVerificationStatus(completion: @escaping (Bool, Error?) -> Void) {
        guard let user = Auth.auth().currentUser else { completion(false, NSError(domain: "Auth", code: 6, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])) ; return }
        user.reload { error in
            if let error = error { completion(false, error); return }
            let verified = user.isEmailVerified
            Task { @MainActor in self.isVerified = verified }
            // refresh token
            user.getIDTokenForcingRefresh(true) { token, tokenError in
                if let tokenError = tokenError { completion(false, tokenError); return }
                completion(verified, nil)
            }
        }
    }

    // MARK: - Nutrislice app-level helpers
    /// Map known local hall IDs to Nutrislice district and school slug. Update as needed.
    private func nutrisliceParamsForHallID(_ hallID: String) -> (district: String, slug: String)? {
        let district = "techdining"
        switch hallID {
        case "1": return (district, "north-ave-dining-hall")
        case "3": return (district, "west-village")
        default: return nil
        }
    }

    /// Compute meal key using the same schedule as the UI. Returns nil if outside meal windows.
    private func mealKeyForNow() -> String? {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: Date())
        if (hour >= 9 && hour < 12) { return "breakfast" }
        if (hour >= 12 && hour < 17) { return "lunch" }
        if (hour >= 17 && hour < 20) { return "dinner" }
        if (hour >= 21 && hour <= 23) || (hour >= 0 && hour < 2) { return "dinner" }
        return nil
    }

    /// Fetch menus for all known Nutrislice-mapped halls when the app launches.
    /// Defaults to "breakfast" if no meal window is active.
    @MainActor
    func fetchMenusOnLaunch() async {
        let mealKey = mealKeyForNow() ?? "breakfast"
        for hall in halls {
            guard let params = nutrisliceParamsForHallID(hall.id) else { continue }
            await fetchMenuFromNutrislice(for: hall.id, district: params.district, schoolSlug: params.slug, meal: mealKey, date: Date(), debugDump: false)
            // small polite pause between requests
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
    }

    // MARK: - Nutrislice integration
    /// Fetch today's menu from Nutrislice for a given hall and update the corresponding `DiningHall.menuItems`.
    /// Uses the shared `NutrisliceService` parser and maps items into the app's `MenuItem` model.
    @MainActor
    func fetchMenuFromNutrislice(for hallID: String, district: String, schoolSlug: String, meal: String = "breakfast", date: Date = Date(), debugDump: Bool = false) async {
        guard let idx = halls.firstIndex(where: { $0.id == hallID }) else { return }
        do {
            // respect DEBUG build or explicit debugDump
            let isDebugBuild: Bool = {
                #if DEBUG
                return true
                #else
                return false
                #endif
            }()
            let doDebug = debugDump || isDebugBuild
            let items = try await NutrisliceService.shared.fetchMenu(district: district, school: schoolSlug, meal: meal, date: date, debugDump: doDebug)
            let mapped: [MenuItem] = items.map { nutri in
                MenuItem(id: nutri.id, name: nutri.name, category: nutri.category, rating: 0.0, reviewCount: 0, labels: nutri.labels)
            }
            halls[idx].menuItems = mapped
            halls[idx].lastUpdated = "just now"
            print("[AppState] fetchMenuFromNutrislice -> updated \(halls[idx].name) with \(mapped.count) items")
        } catch {
            print("[AppState] fetchMenuFromNutrislice error: \(error)")
        }
    }
}
