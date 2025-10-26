//
//  FoodRatingView.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import SwiftUI

struct FoodRatingView: View, Identifiable {
    var id: String { item.id }
    let hall: DiningHall
    let item: MenuItem
    var onSubmit: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selected = 0
    @State private var hovered = 0 // not used on iOS but kept for parity
    @State private var isSubmitting = false
    @State private var showThanks = false
    @EnvironmentObject private var appState: AppState
    @State private var alertMessage: String? = nil
    @State private var showingAuth: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    info
                    rating
                    submit
                    if let msg = alertMessage {
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if showThanks {
                        thanks
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding()
            }
            .navigationTitle("Rate Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        }
        .sheet(isPresented: $showingAuth) { AuthView().environmentObject(appState) }
        .onDisappear(perform: onDisappearReset)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.name).font(.title3).bold()
            Badge(text: item.category, tint: categoryTint(item.category))
            HStack(spacing: 8) {
                Text("Current rating:").font(.caption).foregroundStyle(.secondary)
                RatingStars(rating: item.rating)
                Text(String(format: "%.1f", item.rating)).font(.subheadline).bold()
                Text("(\(item.reviewCount) reviews)").font(.caption).foregroundStyle(.secondary)
            }
        }.card()
    }

    private var rating: some View {
        VStack(spacing: 8) {
            Text("How would you rate this item?").fontWeight(.medium)
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { v in
                    Button(action: { selected = v }) {
                        Image(systemName: (selected >= v) ? "star.fill" : "star")
                            .resizable().scaledToFit().frame(width: 28, height: 28)
                            .foregroundStyle((selected >= v) ? Color.yellow : Color.gray.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(selected >= v ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: selected)
                }
            }
            Text(ratingText)
                .font(.caption)
                .foregroundStyle(selected > 0 ? .primary : .secondary)
        }
    }

    private var submit: some View {
        Button(action: handleSubmit) {
            HStack {
                Image(systemName: isSubmitting ? "checkmark.circle" : (showThanks ? "checkmark.circle.fill" : "hand.thumbsup"))
                    .imageScale(.small)
                    .rotationEffect(.degrees(isSubmitting ? 360 : 0))
                    .animation(.linear(duration: isSubmitting ? 1 : 0), value: isSubmitting)
                if isSubmitting {
                    Text("Submitting...")
                } else if showThanks {
                    Text("Submitted")
                } else {
                    Text("Submit Rating")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(selected == 0 || isSubmitting || showThanks)
    }

    private func handleSubmit() {
        // Require a signed-in & verified GT account before allowing rating submissions
        guard appState.firebaseUser != nil, appState.isVerified else {
            alertMessage = "Please sign in with your @gatech.edu account and verify your email before submitting ratings."
            showingAuth = true
            return
        }
        guard selected > 0 else { return }
        isSubmitting = true
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            onSubmit(selected)
            isSubmitting = false
            withAnimation {
                showThanks = true
            }
        }
    }

    private var thanks: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill").imageScale(.small).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Thanks for your contribution!").font(.subheadline).bold()
                Text("Your feedback helps other students decide what to eat.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var ratingText: String {
        switch selected {
        case 1: return "Poor - Not recommended"
        case 2: return "Fair - Could be better"
        case 3: return "Good - Average quality"
        case 4: return "Very Good - Would recommend"
        case 5: return "Excellent - Outstanding!"
        default: return "Tap a star to rate"
        }
    }

    // Reset the thanks flag when the view disappears so reopened view starts fresh
    private func onDisappearReset() {
        showThanks = false
        isSubmitting = false
    }
}
