//
//  Untitled.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import SwiftUI

@main
struct ForkdApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("app.theme") private var themeRaw: String = Theme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(ThemeManager())
                .preferredColorScheme(Theme(rawValue: themeRaw)?.colorScheme)
        }
    }
}
