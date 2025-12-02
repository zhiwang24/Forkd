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

// Recommendation document synchronized from the external recommender API.
struct Recommendation: Codable {
    struct Pick: Codable {
        let hallId: String
        let name: String
        let reason: String
        let sampleItems: [String]
        let score: Double?
    }
    struct RecWeather: Codable {
        let tempC: Double?
        let precipitation: Double?
        let condition: String?
    }
    let updatedAt: TimeInterval?
    let weather: RecWeather?
    let meal: String?
    let pick: Pick?
}

extension Recommendation {
    private static func string(from any: Any?) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    static func from(data: [String: Any]) -> Recommendation? {
        let updatedAt: TimeInterval? = {
            if let ts = data["updatedAt"] as? TimeInterval { return ts }
            if let num = data["updatedAt"] as? NSNumber { return num.doubleValue }
            if let ts = data["updatedAt"] as? Timestamp { return ts.dateValue().timeIntervalSince1970 }
            return nil
        }()
        let weather: RecWeather? = {
            guard let w = data["weather"] as? [String: Any] else { return nil }
            let temp = (w["tempC"] as? NSNumber)?.doubleValue
            let precip = (w["precipitation"] as? NSNumber)?.doubleValue
            let cond = string(from: w["condition"])
            if temp == nil && precip == nil && cond == nil { return nil }
            return RecWeather(tempC: temp, precipitation: precip, condition: cond)
        }()
        let meal = string(from: data["meal"])
        let pick: Pick? = {
            guard let p = data["pick"] as? [String: Any] else { return nil }
            let hallId = string(from: p["hallId"]) ?? string(from: p["id"])
            let name = string(from: p["name"]) ?? string(from: p["hallName"])
            guard let hid = hallId, let nm = name else { return nil }
            let reason = string(from: p["reason"]) ?? ""
            let samples: [String] = {
                if let arr = p["sampleItems"] as? [String] { return arr }
                if let arr = p["sampleItems"] as? [Any] {
                    return arr.compactMap { string(from: $0) }
                }
                return []
            }()
            let score = (p["score"] as? NSNumber)?.doubleValue
            return Pick(hallId: hid, name: nm, reason: reason, sampleItems: samples, score: score)
        }()
        return Recommendation(updatedAt: updatedAt, weather: weather, meal: meal, pick: pick)
    }
}

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
            if locationManager.lastLocation != nil {
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

    // Recommendation document (written by the external recommender service)
    @Published var recommendation: Recommendation? = nil

    // Firestore listener handle
    private var hallsListener: ListenerRegistration? = nil
    private var recListener: ListenerRegistration? = nil

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
        statusTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in self?.reconcileHallStatuses() }
            }

        // Observe Firebase auth state
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let verified = user?.isEmailVerified ?? false
            Task { @MainActor in
                self?.firebaseUser = user
                self?.isVerified = verified
            }
        }

        // Start listening for halls in Firestore
        Task {
            await startListeningToHallsCollection()
        }
        // Listen for recommendation updates written by the recommender API
        Task {
            await startListeningToRecommendation()
            await fetchRecommendationOnce()
        }
    }

    deinit {
        if let h = authHandle { Auth.auth().removeStateDidChangeListener(h) }
        locationCancellable?.cancel()
        clockCancellable?.cancel()
        statusTimer?.cancel()
        hallsListener?.remove()
        recListener?.remove()
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
                self.halls = self.normalizedHalls(newHalls)
                self.reconcileHallStatuses()
                self.hallsLoading = false
                self.hallsError = nil
            }
        }
    }

    // MARK: - Recommendation listener
    /// Listen to the recommendation document written by the external recommender service.
    func startListeningToRecommendation() async {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        recListener?.remove()
        recListener = Firestore.firestore()
            .collection("recommendations")
            .document("global")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if error != nil { return }
                    guard let data = snapshot?.data() else { return }
                    let rec = Recommendation.from(data: data)
                    self?.recommendation = rec
                }
            }
    }

    /// One-off fetch to prime recommendation state on launch.
    func fetchRecommendationOnce() async {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("recommendations").document("global").getDocument()
            if let data = snap.data() {
                let rec = Recommendation.from(data: data)
                Task { @MainActor in self.recommendation = rec }
            }
        } catch {}
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
            self.halls = self.normalizedHalls(newHalls)
            self.reconcileHallStatuses()
            self.hallsLoading = false
            self.hallsError = nil
        } catch {
            self.hallsLoading = false
            self.hallsError = error.localizedDescription
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
    private let operatingHours = OperatingHoursProvider.shared
    private var statusTimer: AnyCancellable? = nil

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

    func hallIsClosed(_ hallID: String) -> Bool {
        guard let hall = halls.first(where: { $0.id == hallID }) else { return false }
        return hall.status.isClosedState
    }
 
     func updateWaitTime(for hallID: String, to minutes: Int) -> (success: Bool, message: String?) {
        if hallIsClosed(hallID) {
             return (false, "This hall is closed right now.")
         }
         // Enforce verified-user gating
         guard isVerified else {
             let msg = "Please verify your @gatech.edu email before submitting."
             return (false, msg)
         }

        // Client-side geofence check: ensure user is within geofence for this hall
        let geo = checkGeofence(for: hallID)
        guard geo.allowed else {
            return (false, geo.message)
        }

        // Rate limit per-hall per-action
        let action: SubmissionAction = .waitTime
        let allowed = canSubmit(hallID: hallID, action: action)
        guard allowed.allowed else {
            let msg = "Please wait \(Int(allowed.remaining))s before submitting another update for this dining hall."
            return (false, msg)
        }

        recordSubmission(hallID: hallID, action: action)

        var hallVotes = pendingWaitVotes[hallID] ?? [:]
        let currentCount = hallVotes[minutes] ?? 0
        let newCount = currentCount + 1
        hallVotes[minutes] = newCount
        pendingWaitVotes[hallID] = hallVotes
        AnalyticsService.shared.logWaitVoteQueued(hallID: hallID, minutes: minutes, votesRemaining: max(0, waitSubmissionThreshold - newCount))

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
        } catch {}
    }

    func updateStatus(for hallID: String, to newStatus: HallStatus) {
        guard let idx = halls.firstIndex(where: { $0.id == hallID }) else { return }
        halls[idx].status = newStatus
        halls[idx].enforceClosedDisplayStateIfNeeded()
    }
    
    /// Submit seating availability for a given hall (e.g. "Plenty", "Some", "Few", "Packed").
    /// Enforces verified users, geofence, and per-hall cooldown similar to wait time submissions.
    func submitSeating(for hallID: String, seating newSeating: String) -> (success: Bool, message: String?) {
        if hallIsClosed(hallID) {
             return (false, "This hall is closed right now.")
         }
         // Enforce verified-user gating
         guard isVerified else {
             let msg = "Please verify your @gatech.edu email before submitting seating availability."
             return (false, msg)
         }

        // Client-side geofence check
        let geo = checkGeofence(for: hallID)
        guard geo.allowed else {
            return (false, geo.message)
        }

        // Rate limit per-hall per-action
        let action: SubmissionAction = .seating
        let allowed = canSubmit(hallID: hallID, action: action)
        guard allowed.allowed else {
            let msg = "Please wait \(Int(allowed.remaining))s before submitting another seating update for this dining hall."
            return (false, msg)
        }
 
        guard let idx = halls.firstIndex(where: { $0.id == hallID }) else { return (false, nil) }
        halls[idx].seating = newSeating
        halls[idx].seatingLastUpdated = "now"
        halls[idx].seatingVerifiedCount += 1
        // record submission time
        recordSubmission(hallID: hallID, action: action)
        Task { await persistSeatingToFirestore(hallID: hallID, seating: newSeating) }
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
        do { try Auth.auth().signOut(); firebaseUser = nil; isVerified = false } catch {}
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
            await fetchMenuFromNutrislice(for: hall.id, district: params.district, schoolSlug: params.slug, meal: mealKey, date: Date())
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
    }

    func fetchRecommendationFromAPI() async {
        guard let url = URL(string: "https://forkd-rec.vercel.app/api/recommend") else { return }
        var req = URLRequest(url: url)
        req.addValue("apple", forHTTPHeaderField: "x-api-key")
        do { _ = try await URLSession.shared.data(for: req) } catch {}
    }

    // MARK: - Nutrislice integration
    /// Fetch today's menu from Nutrislice for a given hall and update the corresponding `DiningHall.menuItems`.
    /// Uses the shared `NutrisliceService` parser and maps items into the app's `MenuItem` model.
    @MainActor
    func fetchMenuFromNutrislice(for hallID: String, district: String, schoolSlug: String, meal: String = "breakfast", date: Date = Date()) async {
        guard let idx = halls.firstIndex(where: { $0.id == hallID }) else { return }
        do {
            let items = try await NutrisliceService.shared.fetchMenu(district: district, school: schoolSlug, meal: meal, date: date)
            let mapped: [MenuItem] = items.map { nutri in
                MenuItem(id: nutri.id, name: nutri.name, category: nutri.category, labels: nutri.labels)
            }
            halls[idx].menuItems = mapped
        } catch {}
    }

    private func normalizedHalls(_ halls: [DiningHall] ) -> [DiningHall] {
        return halls.map { hall in
            var copy = hall
            copy.enforceClosedDisplayStateIfNeeded()
            return copy
        }
    }

    private func reconcileHallStatuses(now: Date = Date()) {
        guard !halls.isEmpty else { return }
        var dirty: [(String, HallStatus)] = []
        for idx in halls.indices {
            guard let info = operatingHours.displayInfo(for: halls[idx].id, date: now) else { continue }
            let target: HallStatus = info.isOpenNow ? .open : .closed
            if halls[idx].status != target {
                halls[idx].status = target
                halls[idx].enforceClosedDisplayStateIfNeeded()
                dirty.append((halls[idx].id, target))
            }
        }
        guard !dirty.isEmpty else { return }
        Task { await persistHallStatuses(dirty) }
    }

    private func persistHallStatuses(_ updates: [(String, HallStatus)]) async {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        let db = Firestore.firestore()
        for (docID, status) in updates {
            try? await db.collection("halls").document(docID).setData(["status": status.rawValue], merge: true)
        }
    }

    private func persistSeatingToFirestore(hallID: String, seating: String) async {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        let db = Firestore.firestore()
        let formatter = ISO8601DateFormatter()
        let data: [String: Any] = [
            "seating": seating,
            "seatingLastUpdated": formatter.string(from: Date()),
            "seatingVerifiedCount": halls.first(where: { $0.id == hallID })?.seatingVerifiedCount ?? 0
        ]
        try? await db.collection("halls").document(hallID).setData(data, merge: true)
    }
}
