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
            name: "North Ave Dining",
            waitTime: "5-10 min",
            status: .open,
            lastUpdated: "2m ago",
            menuItems: [
                MenuItem(id: "m1", name: "Margherita Pizza", category: "Pizza", rating: 4.2, reviewCount: 128),
                MenuItem(id: "m2", name: "Chicken Caesar", category: "Salads", rating: 3.9, reviewCount: 76),
                MenuItem(id: "m3", name: "Tomato Soup", category: "Soup", rating: 4.5, reviewCount: 52)
            ],
            verifiedCount: 142,
            lat: 33.7712846105461
            lon: -84.39142581349368
        ),
        DiningHall(
            id: "2",
            name: "Brittain",
            waitTime: "10-15 min",
            status: .busy,
            lastUpdated: "5m ago",
            menuItems: [
                MenuItem(id: "m4", name: "Spaghetti Bolognese", category: "Pasta", rating: 4.0, reviewCount: 201),
                MenuItem(id: "m5", name: "Sushi Rolls", category: "Asian", rating: 3.6, reviewCount: 64),
                MenuItem(id: "m6", name: "Turkey Club", category: "Sandwiches", rating: 4.1, reviewCount: 89)
            ],
            verifiedCount: 89,
            lat: 33.77266789537731,
            lon: -84.39129365983848
        ),
        DiningHall(
            id: "3",
            name: "West Village",
            waitTime: "Closed",
            status: .closed,
            lastUpdated: "Today",
            menuItems: [],
            verifiedCount: 5
            ,lat: 33.77982273684821,
            lon: -84.40470500216735
        )
    ]
}
