//
//  Models.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import Foundation

struct MenuItem: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var category: String
    var labels: [String] = []
}

enum HallStatus: String, Codable, CaseIterable { case open, busy, closed, unknown }

struct DiningHall: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var waitTime: String // e.g. "5-10 min"
    var status: HallStatus
    // Use a timestamp for the canonical last-updated moment. Views should render a human-friendly string from this.
    var lastUpdatedAt: TimeInterval? = nil
    var menuItems: [MenuItem]
    var verifiedCount: Int = 0
    var lat: Double? = nil
    var lon: Double? = nil
    var seating: String? = nil
    var seatingLastUpdated: String? = nil
    var seatingVerifiedCount: Int = 0

    // Optional human-readable open/close times (e.g. "9am", "11pm")
    var opensAt: String? = nil
    var closesAt: String? = nil
    var nutrisliceSlug: String? = nil
}

// Small helper to format last-updated timestamps into friendly strings. Keep it as an extension so views can call it via AppState or directly.
extension DiningHall {
    func lastUpdatedText(now: Date = Date()) -> String {
        guard let ts = lastUpdatedAt else { return "Unknown" }
        let elapsed = Int(now.timeIntervalSince1970 - ts)
        if elapsed < 60 { return "now" }
        if elapsed < 3600 { return "\(elapsed / 60)m ago" }
        if elapsed < 86400 { return "\(elapsed / 3600)h ago" }
        // fallback to a short date for older updates
        let d = Date(timeIntervalSince1970: ts)
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: d)
    }
}

// MARK: - Firestore mapping helpers
// Helpers to construct model instances from Firestore document data. These are defensive about types coming from the database.
extension MenuItem {
    /// Create a MenuItem from a Firestore-style dictionary.
    /// Expected keys: id (String) OR provided via docID, name (String), category (String), labels ([String])
    init(from dict: [String: Any], docID: String? = nil) {
        self.id = docID ?? (dict["id"] as? String ?? UUID().uuidString)
        self.name = dict["name"] as? String ?? "Unknown"
        self.category = dict["category"] as? String ?? ""
        if let labels = dict["labels"] as? [String] { self.labels = labels } else { self.labels = [] }
    }
}

extension DiningHall {
    /// Create a DiningHall from a Firestore-style dictionary and document id.
    /// Supports fields: name, lat, lon, waitTime (String) or currentWaitMinutes (Number), lastUpdatedAt (Timestamp or Number), verifiedCount (Number), status (String), menuItems ([Map])
    init(from dict: [String: Any], docID: String) {
        self.id = docID
        self.name = dict["name"] as? String ?? "Unknown Hall"
        // lat/lon
        if let lat = dict["lat"] as? Double { self.lat = lat } else if let lat = dict["lat"] as? NSNumber { self.lat = lat.doubleValue } else { self.lat = nil }
        if let lon = dict["lon"] as? Double { self.lon = lon } else if let lon = dict["lon"] as? NSNumber { self.lon = lon.doubleValue } else { self.lon = nil }

        // waitTime: prefer a numeric minutes field but fall back to the legacy waitTime string
        if let minutes = dict["currentWaitMinutes"] as? Int {
            if minutes < 2 { self.waitTime = "1-2 min" } else { self.waitTime = "\(max(1, minutes-1))-\(minutes+1) min" }
        } else if let minutes = dict["currentWaitMinutes"] as? NSNumber {
            let m = minutes.intValue
            if m < 2 { self.waitTime = "1-2 min" } else { self.waitTime = "\(max(1, m-1))-\(m+1) min" }
        } else {
            self.waitTime = dict["waitTime"] as? String ?? "Unknown"
        }

        // status / isOpen mapping
        if let statusStr = dict["status"] as? String, let s = HallStatus(rawValue: statusStr) {
            self.status = s
        } else if let isOpen = dict["isOpen"] as? Bool {
            self.status = isOpen ? .open : .closed
        } else {
            self.status = .unknown
        }

        // lastUpdatedAt may be stored as a Firestore Timestamp or as a Double/Int seconds-since-1970
        if let ts = dict["lastUpdatedAt"] as? TimeInterval {
            self.lastUpdatedAt = ts
        } else if let tsn = dict["lastUpdatedAt"] as? NSNumber {
            self.lastUpdatedAt = tsn.doubleValue
        } else if let tsDict = dict["lastUpdatedAt"] as? [String: Any], let seconds = tsDict["_seconds"] as? NSNumber {
            // Some Firestore debugger outputs timestamp objects as dictionaries like { "_seconds": 12345, "_nanoseconds": 0 }
            self.lastUpdatedAt = seconds.doubleValue
        } else {
            self.lastUpdatedAt = nil
        }

        if let vc = dict["verifiedCount"] as? Int { self.verifiedCount = vc }
        else if let vc = dict["verifiedCount"] as? NSNumber { self.verifiedCount = vc.intValue }
        else { self.verifiedCount = 0 }

        // Seating and optional fields
        self.seating = dict["seating"] as? String
        self.seatingLastUpdated = dict["seatingLastUpdated"] as? String
        if let sv = dict["seatingVerifiedCount"] as? Int { self.seatingVerifiedCount = sv } else if let sv = dict["seatingVerifiedCount"] as? NSNumber { self.seatingVerifiedCount = sv.intValue } else { self.seatingVerifiedCount = 0 }

        self.opensAt = dict["opensAt"] as? String
        self.closesAt = dict["closesAt"] as? String
        self.nutrisliceSlug = dict["nutrisliceSlug"] as? String

        // menu items may be embedded as an array of maps under "menuItems" or provided externally; parse if present
        var parsedItems: [MenuItem] = []
        if let items = dict["menuItems"] as? [[String: Any]] {
            parsedItems = items.map { MenuItem(from: $0, docID: $0["id"] as? String) }
        }
        self.menuItems = parsedItems
    }
}
