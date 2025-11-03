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
    var rating: Double
    var reviewCount: Int
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
