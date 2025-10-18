//
//  AppState.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var halls: [DiningHall] = SampleData.halls
    @Published var selectedHall: DiningHall? = nil
    @Published var selectedItem: MenuItem? = nil

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
}
