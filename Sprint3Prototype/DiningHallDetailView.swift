//
//  DiningHallDetailView.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import SwiftUI

struct DiningHallDetailView: View {
    @EnvironmentObject private var appState: AppState
    let hall: DiningHall
    @Binding var path: NavigationPath
    @State private var showingWaitInput = false
    @State private var selectedItem: MenuItem? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                waitCard
                menuList
                helpText
            }
            .padding()
        }
        .navigationTitle(hall.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedItem) { item in
            FoodRatingView(hall: hall, item: item) { rating in
                Task { try? await Task.sleep(nanoseconds: 700_000_000) }
                appState.submitRating(for: item.id, in: hall.id, rating: rating)
            }
        }
        .sheet(item: $selectedItem) { item in
            FoodRatingView(
                hall: hall,
                item: item,
                onSubmit: { rating in
                    Task { try? await Task.sleep(nanoseconds: 700_000_000) }
                    appState.submitRating(for: item.id, in: hall.id, rating: rating)
                }
            )
        }
        .sheet(isPresented: $showingWaitInput) {
            WaitTimeInputView(hall: hall)
                .environmentObject(appState)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                Text("Open • Updated \(hall.lastUpdated)").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusDot: some View {
        let color: Color = {
            switch hall.status { case .open: return .green; case .busy: return .yellow; case .closed: return .red; case .unknown: return .gray }
        }()
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    private var waitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .imageScale(.medium)
                        .foregroundStyle(Color.accentColor)
                    Text("Current Wait Time").fontWeight(.medium)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(hall.waitTime)
                        .font(.title2).bold()
                        .foregroundStyle(Color.accentColor)
                    Text("estimated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                showingWaitInput = true
            } label: {
                Label("Update wait time after eating", systemImage: "timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.accentColor.opacity(0.2))
        )
    }

    private var menuList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "person.2")
                Text("Today's Menu").font(.headline)
                Text("(\(hall.menuItems.count) items)").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(hall.menuItems) { item in
                Button {
                    selectedItem = item
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(item.name).fontWeight(.medium)
                                Badge(text: item.category, tint: categoryTint(item.category))
                            }
                            HStack(spacing: 8) {
                                RatingStars(rating: item.rating)
                                Text(String(format: "%.1f", item.rating)).font(.subheadline).fontWeight(.medium)
                                Text("(\(item.reviewCount) reviews)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("Rate").foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var helpText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Thanks for keeping times accurate!").font(.subheadline).bold()
            Text("Share your real wait time after you eat so other students get up-to-date info.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
