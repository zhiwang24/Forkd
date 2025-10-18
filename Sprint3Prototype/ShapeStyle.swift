//
//  Designs.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import SwiftUI

extension Color {
    static let primaryAcc = Color.accentColor
    static let card = Color(UIColor.secondarySystemBackground)
    static let muted = Color.secondary
}

struct Card: ViewModifier { func body(content: Content) -> some View { content
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.5)))
    }
}
extension View { func card() -> some View { modifier(Card()) } }

struct Badge: View {
    var text: String
    var tint: Color = .primaryAcc
    var body: some View {
        Text(text)
            .font(.caption).bold()
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

struct RatingStars: View {
    var rating: Double // 0..5
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { i in
                let filled = i < Int(floor(rating))
                Image(systemName: filled ? "star.fill" : "star")
                    .imageScale(.small)
                    .foregroundStyle(filled ? Color.yellow : Color.gray.opacity(0.4))
            }
        }
        .accessibilityLabel("Rating \(String(format: "%.1f", rating)) out of 5")
    }
}

func categoryTint(_ category: String) -> Color {
    switch category {
    case "Pizza": return .red
    case "Salads": return .green
    case "Main": return .blue
    case "Pasta": return .orange
    case "Asian": return .purple
    case "Mexican": return .pink
    case "Soup": return .indigo
    case "Sandwiches": return .yellow
    default: return .gray
    }
}
