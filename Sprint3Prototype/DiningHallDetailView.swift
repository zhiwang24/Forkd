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
    @State private var showingReportSheet = false
    @State private var showingAuth: Bool = false
    @State private var collapsedStations: Set<String> = []

    private var currentHall: DiningHall {
        appState.halls.first(where: { $0.id == hall.id }) ?? hall
    }

    private func isCollapsed(_ category: String) -> Bool {
        collapsedStations.contains(category)
    }

    private func toggleCollapsed(_ category: String) {
        if collapsedStations.contains(category) {
            collapsedStations.remove(category)
        } else {
            collapsedStations.insert(category)
        }
    }

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
        .task {
            await loadNutrisliceMenuIfAvailable()
        }
        .onReceive(appState.$isVerified) { verified in
            // If the user just became verified and there is a post-auth intent for this hall, open the wait-time input automatically.
            if verified {
                if let target = appState.postAuthOpenWaitHallID, target == hall.id {
                    showingWaitInput = true
                    appState.clearPostAuthIntent()
                }
            }
        }
        .sheet(isPresented: $showingReportSheet) {
            ReportMenuView(hall: currentHall)
                .environmentObject(appState)
        }
        .sheet(item: $selectedItem) { item in
            FoodRatingView(hall: hall, item: item) { rating in
                // Call AppState.submitRating which now returns (Bool, String?) to indicate success or blocked reason
                return appState.submitRating(for: item.id, in: hall.id, rating: rating)
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $showingAuth) {
            AuthView().environmentObject(appState)
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
                Text("Open • Updated \(currentHall.lastUpdated)").font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").imageScale(.small).foregroundStyle(.green)
                    Text("Verified by \(currentHall.verifiedCount) student\(currentHall.verifiedCount == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        // DEBUG: Long-press the header to trigger a debug fetch that prints + writes the raw Nutrislice JSON for inspection.
        .onLongPressGesture {
            Task {
                await loadNutrisliceMenuIfAvailable(debugDump: true)
            }
        }
    }

    private var statusDot: some View {
        let color: Color = {
            switch currentHall.status { case .open: return .green; case .busy: return .yellow; case .closed: return .red; case .unknown: return .gray }
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
                    Text(currentHall.waitTime)
                        .font(.title2).bold()
                        .foregroundStyle(Color.accentColor)
                    Text("estimated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                if appState.firebaseUser != nil && appState.isVerified {
                    showingWaitInput = true
                } else {
                    // record intent so after signing in / verifying the app can automatically open the wait time input
                    appState.setPostAuthOpenWaitIntent(hallID: hall.id)
                    showingAuth = true
                }
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
                Text("(\(currentHall.menuItems.count) items)").font(.subheadline).foregroundStyle(.secondary)
            }

            let grouped = Dictionary(grouping: currentHall.menuItems, by: { $0.category.isEmpty ? "Other" : $0.category })
            let sortedCategories = grouped.keys.sorted()

            ForEach(sortedCategories, id: \ .self) { category in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: { withAnimation { toggleCollapsed(category) } }) {
                            HStack(alignment: .center, spacing: 8) {
                                Image(systemName: isCollapsed(category) ? "chevron.right" : "chevron.down")
                                    .foregroundStyle(.secondary)
                                Text(category).font(.subheadline).fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("\(grouped[category]?.count ?? 0) items").font(.caption).foregroundStyle(.secondary)
                    }

                    if !isCollapsed(category) {
                        LazyVStack(spacing: 8) {
                            ForEach(grouped[category] ?? [], id: \ .id) { item in
                                Button {
                                    if appState.firebaseUser != nil && appState.isVerified {
                                        selectedItem = item
                                    } else {
                                        showingAuth = true
                                    }
                                } label: {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 8) {
                                                Text(item.name).fontWeight(.medium)
                                            }
                                            HStack(spacing: 8) {
                                                RatingStars(rating: item.rating)
                                                Text(String(format: "%.1f", item.rating)).font(.subheadline).fontWeight(.medium)
                                                Text("(\(item.reviewCount) reviews)").font(.caption).foregroundStyle(.secondary)
                                            }
                                            // Labels (allergens/tags) from Nutrislice — show small chips
                                            if !item.labels.isEmpty {
                                                HStack(spacing: 6) {
                                                    ForEach(item.labels, id: \.self) { label in
                                                        Text(label)
                                                            .font(.caption2)
                                                            .padding(.vertical, 4)
                                                            .padding(.horizontal, 6)
                                                            .background(Color.secondary.opacity(0.12))
                                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                                    }
                                                }
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
                }
            }
        }
    }

    private var helpText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Thanks for keeping times accurate!").font(.subheadline).bold()
            Text("Share your real wait time after you eat so other students get up-to-date info.")
                .font(.caption).foregroundStyle(.secondary)
            
            Button {
                showingReportSheet = true
            } label: {
                Label("Report incorrect menu information", systemImage: "exclamationmark.bubble")
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Nutrislice loader
    /// Map known dining halls to nutrislice slugs and fetch today's breakfast menu.
    private func nutrisliceParams(for hall: DiningHall) -> (district: String, slug: String)? {
        // Georgia Tech Nutrislice district
        let district = "techdining"
        switch hall.id {
        case "1": // North Ave Dining (sample data id)
            return (district, "north-ave-dining-hall")
        case "3": // West Village (sample data id)
            return (district, "west-village")
        default:
            return nil
        }
    }

    // MARK: - Time / meal helpers
    /// Returns the current meal key according to the schedule:
    /// - Breakfast: 9:00 - 11:59 (9-12)
    /// - Lunch: 12:00 - 16:59 (12-17)
    /// - Dinner: 17:00 - 19:59 (17-20)
    /// - Overnight: 21:00 - 01:59 (21-2) -> mapped to "dinner" for Nutrislice because Nutrislice deployments typically use breakfast/lunch/dinner.
    /// Times are local device times. If the current time doesn't fall into any bucket, method returns nil.
    private func currentMealKey(for date: Date = Date()) -> String? {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)

        if (hour >= 9 && hour < 12) { return "breakfast" }
        if (hour >= 12 && hour < 17) { return "lunch" }
        if (hour >= 17 && hour < 20) { return "dinner" }
        // overnight: 21-23 or 0-1
        if (hour >= 21 && hour <= 23) || (hour >= 0 && hour < 2) { return "dinner" } // map overnight to dinner

        return nil
    }

    private func loadNutrisliceMenuIfAvailable(debugDump: Bool = false) async {
        guard let params = nutrisliceParams(for: currentHall) else { return }
        // If debugDump is requested, allow fetching even outside the strict meal windows so developers
        // can inspect raw JSON at any time. When no meal window applies, pick a sensible default (breakfast).
        let mealKey = currentMealKey()
        if mealKey == nil && !debugDump { return } // in normal mode, do not fetch outside meal windows
        let effectiveMeal = mealKey ?? "breakfast"
        await appState.fetchMenuFromNutrislice(for: currentHall.id, district: params.district, schoolSlug: params.slug, meal: effectiveMeal, debugDump: debugDump)
    }
}
