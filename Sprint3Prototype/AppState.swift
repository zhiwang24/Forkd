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
import CoreLocation
import Combine

@MainActor
final class AppState: ObservableObject {
    // Location manager for client-side geofence checks
    @Published var locationManager = LocationManager()

    // Forwarding cancellable so we can notify observers when the LocationManager's internal state changes
    private var locationCancellable: AnyCancellable? = nil

    // Geofence configuration (meters)
    let geofenceRadiusMeters: Double = 150
    let geofenceMaxAccuracyMeters: Double = 100

    // User preference: metric vs imperial (persisted in UserDefaults)
    @Published var prefersMetric: Bool = UserDefaults.standard.bool(forKey: "app.units.metric") {
        didSet {
            UserDefaults.standard.set(prefersMetric, forKey: "app.units.metric")
        }
    }

    // Helper: format meters into a user-facing imperial string (feet or miles)
    private func imperialString(fromMeters meters: Double) -> String {
        let mileInMeters = 1609.344
        if meters >= mileInMeters {
            return String(format: "%.1f mi", meters / mileInMeters)
        } else {
            return String(format: "%.0f ft", meters * 3.28084)
        }
    }

    // Helper: format meters into a user-facing metric string (meters or kilometers)
    private func metricString(fromMeters meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000.0)
        } else {
            return String(format: "%.0f m", meters)
        }
    }

    // Unified formatter that respects user preference
    func formattedDistance(fromMeters meters: Double) -> String {
        return prefersMetric ? metricString(fromMeters: meters) : imperialString(fromMeters: meters)
    }

    /// Post-location intent: when we request permission we may want to continue a pending action automatically once the user grants permission.
    enum PostLocationIntent: Equatable {
        case wait(hallID: String, minutes: Int)
        case seating(hallID: String, seating: String)
        case waitAndSeating(hallID: String, minutes: Int, seating: String?)
    }

    @Published var pendingLocationIntent: PostLocationIntent? = nil

    func setPendingLocationIntent(_ intent: PostLocationIntent?) {
        pendingLocationIntent = intent
    }

    func clearPendingLocationIntent() {
        pendingLocationIntent = nil
    }

    // Clock that ticks every minute so UI can update relative time labels like "now" / "2m ago".
    @Published var now: Date = Date()
    private var clockCancellable: AnyCancellable? = nil

    /// Check whether the user's last known location is within the geofence for a given hall.
    /// Returns (allowed: Bool, message: String?) where message explains failures.
    func checkGeofence(for hallID: String) -> (allowed: Bool, message: String?) {
        guard let hall = halls.first(where: { $0.id == hallID }) else { return (true, nil) }
        guard let lat = hall.lat, let lon = hall.lon else {
            // No coordinates configured for this hall - allow submission (server-side may validate later)
            return (true, nil)
        }
        let auth = locationManager.authorizationStatus
        switch auth {
        case .authorizedAlways, .authorizedWhenInUse:
            // Ensure we have a location
            if let last = locationManager.lastLocation {
                let res = locationManager.isWithinGeofence(lat: lat, lon: lon, radiusMeters: geofenceRadiusMeters, maxAccuracyMeters: geofenceMaxAccuracyMeters)
                if res.inside { return (true, nil) }
                let distText = res.distance != nil ? formattedDistance(fromMeters: res.distance!) : "unknown"
                let radiusText = formattedDistance(fromMeters: geofenceRadiusMeters)
                return (false, "You seem to be \(distText) away from the dining hall! You must be within \(radiusText) to submit.")
            } else {
                return (false, "Location unavailable — please allow location access and try again.")
            }
        case .notDetermined:
            return (false, "Location permission not requested yet")
        case .restricted, .denied:
            return (false, "Location access denied. Allow location access in Settings to verify submissions.")
        @unknown default:
            return (false, "Location unavailable")
        }
    }

    // Firestore-backed halls state (replaces previous SampleData fallback)
    @Published var halls: [DiningHall] = []
    @Published var hallsLoading: Bool = true
    @Published var hallsError: String? = nil

    @Published var selectedHall: DiningHall? = nil

    // Firestore listener handle
    private var hallsListener: ListenerRegistration? = nil

    // Firebase auth user
    @Published var firebaseUser: User? = Auth.auth().currentUser
    @Published var isVerified: Bool = Auth.auth().currentUser?.isEmailVerified ?? false

    // Post-auth intent: when a user is sent to AuthView, we can record an intent to automatically open a target UI after successful sign-in/verification.
    @Published var postAuthOpenWaitHallID: String? = nil

    func setPostAuthOpenWaitIntent(hallID: String) {
        postAuthOpenWaitHallID = hallID
    }

    func clearPostAuthIntent() {
        postAuthOpenWaitHallID = nil
    }

    private var authHandle: AuthStateDidChangeListenerHandle? = nil

    init() {
        // Subscribe to locationManager.objectWillChange and forward it through AppState's objectWillChange
        locationCancellable = locationManager.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
            }
        }

        // Periodic clock to refresh relative time UI
        clockCancellable = Timer.publish(every: 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                Task { @MainActor in self?.now = date }
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

        // Start listening for halls in Firestore
        Task {
            await startListeningToHallsCollection()
        }
    }

    deinit {
        if let h = authHandle { Auth.auth().removeStateDidChangeListener(h) }
        locationCancellable?.cancel()
        clockCancellable?.cancel()
        hallsListener?.remove()
    }

    // MARK: - Firestore halls integration
    /// Begin listening to the `halls` collection in Firestore and map documents into `DiningHall` instances.
    func startListeningToHallsCollection() async {
        // Ensure Firebase is configured
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        let db = Firestore.firestore()
        // Listen for realtime updates
        self.hallsLoading = true
        self.hallsError = nil
        hallsListener?.remove()
        hallsListener = db.collection("halls").addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    self.hallsLoading = false
                    self.hallsError = error.localizedDescription
                    print("[AppState] halls listener error: \(error)")
                    return
                }
                guard let snapshot = snapshot else {
                    self.hallsLoading = false
                    self.hallsError = "No data"
                    return
                }
                var newHalls: [DiningHall] = []
                for doc in snapshot.documents {
                    let data = doc.data()
                    let hall = DiningHall(from: data, docID: doc.documentID)
                    newHalls.append(hall)
                }
                // Sort by name to keep deterministic order when not using proximity
                newHalls.sort { $0.name < $1.name }
                self.halls = newHalls
                self.hallsLoading = false
                self.hallsError = nil
            }
        }
    }

    /// Force refresh halls snapshot by fetching once.
    func refreshHallsOnce() async {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        let db = Firestore.firestore()
        self.hallsLoading = true
        self.hallsError = nil
        do {
            let snapshot = try await db.collection("halls").getDocuments()
            var newHalls: [DiningHall] = []
            for doc in snapshot.documents {
                let hall = DiningHall(from: doc.data(), docID: doc.documentID)
                newHalls.append(hall)
            }
            newHalls.sort { $0.name < $1.name }
            self.halls = newHalls
            self.hallsLoading = false
            self.hallsError = nil
        } catch {
            self.hallsLoading = false
            self.hallsError = error.localizedDescription
            print("[AppState] refreshHallsOnce error: \(error)")
        }
    }

    // ===== Submission gating & client-side cooldowns =====
    // Persist per-hall+action last-submission timestamps to UserDefaults to prevent rapid repeat submissions.
    private enum SubmissionAction: String {
        case waitTime = "waitTime"
        case seating = "seating"
    }

    // Default cooldown window in seconds (5 minutes). Tweakable for experiments.
    private let submissionCooldownSeconds: TimeInterval = 5 * 60
    private let waitSubmissionThreshold = 5
    private var pendingWaitVotes: [String: [Int: Int]] = [:]

    private func lastSubmissionKey(hallID: String, action: SubmissionAction) -> String {
        return "lastSubmission:\(hallID):\(action.rawValue)"
    }

    /// Returns (allowed, remainingSeconds).
    private func canSubmit(hallID: String, action: SubmissionAction) -> (allowed: Bool, remaining: TimeInterval) {
        let key = lastSubmissionKey(hallID: hallID, action: action)
        let last = UserDefaults.standard.double(forKey: key) // 0.0 if missing
        let now = Date().timeIntervalSince1970
        if last == 0 { return (true, 0) }
        let elapsed = now - last
        if elapsed >= submissionCooldownSeconds { return (true, 0) }
        return (false, submissionCooldownSeconds - elapsed)
    }

    private func recordSubmission(hallID: String, action: SubmissionAction) {
        let key = lastSubmissionKey(hallID: hallID, action: action)
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: key)
        // Ensure changes are written out quickly
        UserDefaults.standard.synchronize()
    }

    /// Public helper for UI to show remaining cooldown in seconds (0 means allowed now)
    func submissionCooldownRemainingSeconds(hallID: String, actionRaw: String) -> TimeInterval {
        guard let action = SubmissionAction(rawValue: actionRaw) else { return 0 }
        let res = canSubmit(hallID: hallID, action: action)
        return res.allowed ? 0 : res.remaining
    }

    func updateWaitTime(for hallID: String, to minutes: Int) -> (success: Bool, message: String?) {
        // Enforce verified-user gating
        guard isVerified else {
            let msg = "Please verify your @gatech.edu email before submitting."
            print("[AppState] updateWaitTime - blocked: user not verified")
            return (false, msg)
        }

        // Client-side geofence check: ensure user is within geofence for this hall
        let geo = checkGeofence(for: hallID)
        guard geo.allowed else {
            print("[AppState] updateWaitTime - blocked by geofence: \(geo.message ?? "no location")")
            return (false, geo.message)
        }

        // Rate limit per-hall per-action
        let action: SubmissionAction = .waitTime
        let allowed = canSubmit(hallID: hallID, action: action)
        guard allowed.allowed else {
            let msg = "Please wait \(Int(allowed.remaining))s before submitting another update for this dining hall."
            print("[AppState] updateWaitTime - blocked by cooldown, remaining: \(Int(allowed.remaining))s")
            return (false, msg)
        }

        recordSubmission(hallID: hallID, action: action)

        var hallVotes = pendingWaitVotes[hallID] ?? [:]
        let currentCount = hallVotes[minutes] ?? 0
        let newCount = currentCount + 1
        hallVotes[minutes] = newCount
        pendingWaitVotes[hallID] = hallVotes
        AnalyticsService.shared.logWaitVoteQueued(hallID: hallID, minutes: minutes, votesRemaining: max(0, waitSubmissionThreshold - newCount))
        print("[AppState] updateWaitTime - queued vote for \(hallID) @ \(minutes) min (\(newCount)/\(waitSubmissionThreshold))")

        if newCount < waitSubmissionThreshold {
            return (true, "Thanks! We'll update once enough students agree.")
        }

        // Threshold reached: commit the update and reset the counter for this minutes bucket
        hallVotes[minutes] = 0
        pendingWaitVotes[hallID] = hallVotes

        guard let idx = halls.firstIndex(where: { $0.id == hallID }) else { return (false, "Hall not found") }
        let newText = minutes < 2 ? "1-2 min" : "\(max(1, minutes-1))-\(minutes+1) min"
        halls[idx].waitTime = newText
        halls[idx].lastUpdatedAt = Date().timeIntervalSince1970
        halls[idx].verifiedCount += waitSubmissionThreshold
        AnalyticsService.shared.logWaitTimeCommitted(hallID: hallID, minutes: minutes, wasAggregated: true)

        Task { await persistWaitTimeToFirestore(hallID: hallID, minutes: minutes) }

        print("[AppState] updateWaitTime - applied aggregated update for \(halls[idx].name) -> \(newText)")
        return (true, nil)
    }

    private func persistWaitTimeToFirestore(hallID: String, minutes: Int) async {
        guard FirebaseApp.app() != nil || { FirebaseApp.configure(); return true }() else { return }
        let db = Firestore.firestore()
        let newText = minutes < 2 ? "1-2 min" : "\(max(1, minutes-1))-\(minutes+1) min"
        let data: [String: Any] = [
            "currentWaitMinutes": minutes,
            "waitTime": newText,
            "lastUpdatedAt": Date().timeIntervalSince1970,
            "verifiedCount": halls.first(where: { $0.id == hallID })?.verifiedCount ?? 0
        ]
        do {
            try await db.collection("halls").document(hallID).setData(data, merge: true)
            print("[AppState] persistWaitTimeToFirestore - updated \(hallID)")
        } catch {
            print("[AppState] persistWaitTimeToFirestore error: \(error)")
        }
    }

    func updateStatus(for hallID: String, to newStatus: HallStatus) {
        guard let idx = halls.firstIndex(where: { $0.id == hallID }) else { return }
        halls[idx].status = newStatus
    }
    
    func submitRating(for itemID: String, in hallID: String, rating newRating: Int) -> (success: Bool, message: String?) {
        return (false, "Ratings are no longer supported.")
    }
    
    /// Submit seating availability for a given hall (e.g. "Plenty", "Some", "Few", "Packed").
    /// Enforces verified users, geofence, and per-hall cooldown similar to wait time submissions.
    func submitSeating(for hallID: String, seating newSeating: String) -> (success: Bool, message: String?) {
        // Enforce verified-user gating
        guard isVerified else {
            let msg = "Please verify your @gatech.edu email before submitting seating availability."
            print("[AppState] submitSeating - blocked: user not verified")
            return (false, msg)
        }

        // Client-side geofence check
        let geo = checkGeofence(for: hallID)
        guard geo.allowed else {
            print("[AppState] submitSeating - blocked by geofence: \(geo.message ?? "no location")")
            return (false, geo.message)
        }

        // Rate limit per-hall per-action
        let action: SubmissionAction = .seating
        let allowed = canSubmit(hallID: hallID, action: action)
        guard allowed.allowed else {
            let msg = "Please wait \(Int(allowed.remaining))s before submitting another seating update for this dining hall."
            print("[AppState] submitSeating - blocked by cooldown, remaining: \(Int(allowed.remaining))s")
            return (false, msg)
        }

        guard let idx = halls.firstIndex(where: { $0.id == hallID }) else { return (false, nil) }
        halls[idx].seating = newSeating
        halls[idx].seatingLastUpdated = "now"
        halls[idx].seatingVerifiedCount += 1
        // record submission time
        recordSubmission(hallID: hallID, action: action)
        print("[AppState] submitSeating - \(halls[idx].name) seating -> \(newSeating), verifiedCount -> \(halls[idx].seatingVerifiedCount)")
        return (true, nil)
    }
    
    // MARK: - Authentication helpers
    func signUp(firstName: String, lastName: String, email: String, password: String, completion: @escaping (Error?) -> Void) {
        let lower = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.hasSuffix("@gatech.edu") else {
            completion(NSError(domain: "SignUp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Please use a @gatech.edu email."]))
            return
        }
        Auth.auth().createUser(withEmail: lower, password: password) { result, error in
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
        guard let hall = halls.first(where: { $0.id == hallID }), let slug = hall.nutrisliceSlug, !slug.isEmpty else { return nil }
        return (district, slug)
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
                MenuItem(id: nutri.id, name: nutri.name, category: nutri.category, labels: nutri.labels)
            }
            halls[idx].menuItems = mapped
            print("[AppState] fetchMenuFromNutrislice -> updated \(halls[idx].name) with \(mapped.count) items")
        } catch {
            print("[AppState] fetchMenuFromNutrislice error: \(error)")
        }
    }
}
