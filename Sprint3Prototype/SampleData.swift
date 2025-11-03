//
//  SampleData.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import Foundation

enum SampleData {
    static let halls: [DiningHall] = [
        DiningHall(
            id: "1",
            name: "North Ave",
            waitTime: "5-10 min",
            status: .open,
            lastUpdatedAt: Date().addingTimeInterval(-2 * 60).timeIntervalSince1970,
            menuItems: [],
            verifiedCount: 142,
            lat: 33.7712846105461,
            lon: -84.39142581349368,
            seating: "Some",
            seatingLastUpdated: "Now",
            seatingVerifiedCount: 34,
            opensAt: "7am",
            closesAt: "8pm"
        ),
        DiningHall(
            id: "2",
            name: "Brittain",
            waitTime: "Closed",
            status: .unknown,
            lastUpdatedAt: Date().timeIntervalSince1970,
            menuItems: [],
            verifiedCount: 89,
            lat: 33.77266789537731,
            lon: -84.39129365983848,
            seating: "Closed",
            seatingLastUpdated: "Now",
            seatingVerifiedCount: 0,
            opensAt: "11am",
            closesAt: "8pm"
        ),
        DiningHall(
            id: "3",
            name: "West Village",
            waitTime: "5-10 min",
            status: .open,
            lastUpdatedAt: Date().addingTimeInterval(-30).timeIntervalSince1970,
            menuItems: [],
            verifiedCount: 5,
            lat: 33.77982273684821,
            lon: -84.40470500216735,
            seating: "Packed",
            seatingLastUpdated: "Now",
            seatingVerifiedCount: 2,
            opensAt: "8am",
            closesAt: "11pm"
        )
    ]
}
