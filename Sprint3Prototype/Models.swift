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
    var lastUpdated: String
    var menuItems: [MenuItem]
    var verifiedCount: Int = 0
}
