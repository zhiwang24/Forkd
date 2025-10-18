//
//  Theme.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import SwiftUI

enum Theme: String, CaseIterable { case system, light, dark
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    var iconName: String { self == .dark ? "sun.max.fill" : "moon.fill" }
    var label: String { switch self { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" } }
}

final class ThemeManager: ObservableObject {
    @AppStorage("app.theme") private var themeRaw: String = Theme.system.rawValue
    @Published var theme: Theme

    init() {
        // read directly from UserDefaults before self exists
        let saved = UserDefaults.standard.string(forKey: "app.theme") ?? Theme.system.rawValue
        theme = Theme(rawValue: saved) ?? .system
    }

    func toggle() {
        switch theme {
        case .system: theme = .dark
        case .dark: theme = .light
        case .light: theme = .system
        }
        themeRaw = theme.rawValue
        objectWillChange.send()
    }
}
