//
//  DiningHallDetailView.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import SwiftUI
import UIKit
import FirebaseFirestore

struct DiningHallDetailView: View {
    @EnvironmentObject private var appState: AppState
    let hall: DiningHall
    @Binding var path: NavigationPath
    @State private var showingWaitInput = false
    @State private var showingReportSheet = false
    @State private var showingAuth: Bool = false
    @State private var menuSearch: String = ""
    @State private var collapsedStations: Set<String> = []

    private var currentHall: DiningHall {
        appState.halls.first(where: { $0.id == hall.id }) ?? hall
    }
    private var hallIsClosed: Bool { appState.hallIsClosed(currentHall.id) }

    // Initialize collapsedStations to include all stations so the UI begins collapsed.
    private func initializeCollapsedIfNeeded() {
        // Don't overwrite if user already toggled
        if !collapsedStations.isEmpty { return }
        let categories = Set(currentHall.menuItems.map { $0.category.isEmpty ? "Other" : $0.category })
        collapsedStations = categories
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
        .task { await loadNutrisliceMenuIfAvailable() }
        .onAppear { initializeCollapsedIfNeeded() }
        .onChange(of: currentHall.menuItems.count) { _, _ in initializeCollapsedIfNeeded() }
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Updated \(currentHall.lastUpdatedText(now: appState.now))").font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").imageScale(.small).foregroundStyle(.green)
                    Text("Verified by \(currentHall.verifiedCount) student\(currentHall.verifiedCount == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .onLongPressGesture {
            Task { await loadNutrisliceMenuIfAvailable(force: true) }
        }
    }

    private var statusDot: some View {
        let color: Color = {
            switch currentHall.status {
            case .open: return .green
            case .busy: return .yellow
            case .closed, .unknown: return .red
            }
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
                    Text(hallIsClosed ? "closed" : "estimated")
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
            .disabled(hallIsClosed)
            if hallIsClosed {
                let message = (currentHall.status == .unknown || currentHall.id == "brittain")
                    ? "This hall is temporarily closed, so new wait reports are paused."
                    : "This hall is closed, so new wait reports are paused."
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

            // Search field for today's menu
            // Custom search bar with icon and clear button
            searchBar

            let trimmedSearch = menuSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            let isSearching = trimmedSearch.isEmpty == false
            // Filter items based on the search text (case-insensitive match on name or category)
            let filtered: [MenuItem] = currentHall.menuItems.filter { item in
                guard isSearching else { return true }
                if item.name.range(of: trimmedSearch, options: .caseInsensitive) != nil { return true }
                if item.category.range(of: trimmedSearch, options: .caseInsensitive) != nil { return true }
                return false
            }
            let groupedItems = Dictionary(grouping: filtered, by: { $0.category.isEmpty ? "Other" : $0.category })
            let sortedCategories = groupedItems.keys.sorted()

            if filtered.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No menu items match your search.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Try removing filters or check a different dining hall.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical)
            } else {
                ForEach(sortedCategories, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 8) {
                        // Compute searching/collapse state at the VStack level so it is visible to both the header HStack and the content below.
                        let hasMatches = ((groupedItems[category] ?? []).isEmpty == false)
                        // A category is effectively collapsed when it is in collapsedStations and we're not in a search that has matches for it.
                        let isEffectivelyCollapsed = isCollapsed(category) && !(isSearching && hasMatches)

                        HStack(spacing: 8) {
                            Button(action: { withAnimation { toggleCollapsed(category) } }) {
                                HStack(alignment: .center, spacing: 8) {
                                    Image(systemName: isEffectivelyCollapsed ? "chevron.right" : "chevron.down")
                                        .foregroundStyle(.secondary)
                                    Text(category).font(.subheadline).fontWeight(.semibold)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Text("\(groupedItems[category]?.count ?? 0) items").font(.caption).foregroundStyle(.secondary)
                        }

                        if !isEffectivelyCollapsed {
                            LazyVStack(spacing: 6) {
                                ForEach(groupedItems[category] ?? [], id: \ .id) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.primary)
                                            if !item.labels.isEmpty {
                                                HStack(spacing: 4) {
                                                    ForEach(item.labels, id: \ .self) { label in
                                                        Text(label)
                                                            .font(.caption2)
                                                            .padding(.vertical, 2)
                                                            .padding(.horizontal, 4)
                                                            .background(Color.secondary.opacity(0.1))
                                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                                    }
                                                }
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 10)
                                    .background(Color.card)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search menu items", text: $menuSearch)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if !menuSearch.isEmpty {
                Button(action: { menuSearch = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.03))
        )
        .padding(.vertical, 2)
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
        let district = "techdining"
        guard let slug = hall.nutrisliceSlug, !slug.isEmpty else { return nil }
        return (district, slug)
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
        if (hour >= 21 && hour <= 23) || (hour >= 0 && hour < 2) { return "dinner" } // map overnight to dinner

        return nil
    }

    private func loadNutrisliceMenuIfAvailable(force: Bool = false) async {
        guard let params = nutrisliceParams(for: currentHall) else { return }
        if !force, currentHall.menuItems.isEmpty == false { return }
        let mealKey = currentMealKey() ?? "breakfast"
        await appState.fetchMenuFromNutrislice(for: currentHall.id, district: params.district, schoolSlug: params.slug, meal: mealKey)
    }
}
