//
//  ContentView.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var path = NavigationPath()
    @State private var showingBugReport = false
    @State private var showingAuth = false
    @State private var showingProfile = false

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                // Show loading / error / content states for halls
                Group {
                    if appState.hallsLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading dining halls...").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let err = appState.hallsError {
                        ScrollView {
                            VStack(alignment: .center, spacing: 12) {
                                Text("Failed to load dining halls").font(.headline)
                                Text(err).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button("Retry") {
                                    Task { await appState.refreshHallsOnce() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding()
                        }
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                header
                                ForEach(sortedHalls) { hall in
                                    HallRow(hall: hall) {
                                        appState.selectedHall = hall
                                        path.append(hall)
                                    }
                                }
                                footer
                            }
                            .padding()
                        }
                        .refreshable {
                            // Pull-to-refresh: refresh menus and request a fresh location update
                            await appState.fetchMenusOnLaunch()
                            appState.locationManager.requestLocation()
                            await appState.refreshHallsOnce()
                        }
                        .navigationDestination(for: DiningHall.self) { hall in
                            DiningHallDetailView(hall: hall, path: $path)
                        }
                    }
                }
            }

            // Floating bug report button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        showingBugReport = true
                    } label: {
                        Image(systemName: "ladybug.fill")
                            .imageScale(.small)
                            .foregroundColor(colorScheme == .dark ? Color.pink.opacity(0.95) : Color.red)
                            .padding(14)
                    }
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.95))
                     .clipShape(Circle())
                     .overlay(Circle().stroke(Color.accentColor.opacity(0.12), lineWidth: 1))
                     .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 6, x: 0, y: 4)
                     .padding(.trailing, 16)
                     .padding(.bottom, 20)
                     .buttonStyle(.plain)
                 }
             }
         }
        .sheet(isPresented: $showingBugReport) {
            BugReportView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showingAuth) {
            AuthView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                .environmentObject(appState)
        }
        .onAppear {
            let list = appState.halls.map { "\($0.name): \($0.verifiedCount)" }.joined(separator: ", ")
            print("[ContentView] onAppear - halls verified counts -> \(list)")
            // Fetch Nutrislice menus for known halls on app launch so menus are up-to-date immediately.
            Task {
                await appState.fetchMenusOnLaunch()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    if appState.firebaseUser == nil {
                        showingAuth = true
                    } else {
                        showingProfile = true
                    }
                } label: {
                    if let user = appState.firebaseUser {
                        let initials = (user.displayName ?? "").split(separator: " ").compactMap { $0.first }.map { String($0) }.joined()
                        Text(initials.isEmpty ? "Me" : initials)
                            .font(.subheadline).bold()
                            .padding(8)
                            .background(Circle().fill(Color.accentColor.opacity(0.12)))
                    } else {
                        Image(systemName: "person.crop.circle")
                            .imageScale(.large)
                            .padding(6)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    theme.toggle()
                } label: {
                    Image(systemName: Theme(rawValue: UserDefaults.standard.string(forKey: "app.theme") ?? Theme.system.rawValue)?.iconName ?? "moon.fill")
                        .imageScale(.small)
                        .padding(8)
                }
                .buttonStyle(.bordered)
            }
            Text("Fork'd").font(.largeTitle).bold().foregroundStyle(Color.accentColor)
            Text("Find the shortest wait times on campus")
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "clock").imageScale(.small)
                Text("Live data • Updated by students").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill").imageScale(.small).foregroundStyle(Color.accentColor)
                Text("Powered by student data").font(.subheadline).bold()
            }
            Text("Help keep wait times accurate by sharing your experience after eating!")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .card()
        .padding(.top, 8)
    }

    // Halls sorted by proximity to the user's last known location.
    // Halls with a calculable distance appear first (closest -> farthest). Halls without location/distance are ordered by name and appear last.
    private var sortedHalls: [DiningHall] {
        let mgr = appState.locationManager
        return appState.halls.sorted { a, b in
            func distance(for h: DiningHall) -> Double? {
                guard let lat = h.lat, let lon = h.lon else { return nil }
                return mgr.distanceTo(lat: lat, lon: lon)
            }
            let da = distance(for: a)
            let db = distance(for: b)
            switch (da, db) {
            case let (a?, b?): return a < b
            case (nil, nil): return a.name < b.name
            case (nil, _?): return false
            case (_?, nil): return true
            }
        }
    }
}

struct HallRow: View {
    var hall: DiningHall
    var onTap: () -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse").imageScale(.small).foregroundStyle(.secondary)
                        Text(hall.name).font(.headline)
                    }
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock").imageScale(.small).foregroundStyle(Color.accentColor)
                            Text(hall.waitTime).fontWeight(.semibold).foregroundStyle(Color.accentColor)
                        }
                        seatingIndicator
                    }
                    HStack(spacing: 6) {
                        openClosedLabel
                    }
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2").imageScale(.small)
                            Text("\(hall.menuItems.count) items available").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .imageScale(.small)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Verified by \(hall.verifiedCount) student\(hall.verifiedCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                        }
                    }
                    .layoutPriority(1)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    // Actionable distance UI: show formatted distance if available, otherwise provide request/open-settings actions.
                    if let lat = hall.lat, let lon = hall.lon {
                        if let meters = appState.locationManager.distanceTo(lat: lat, lon: lon) {
                            // show distance
                            HStack(spacing: 6) {
                                Image(systemName: "location.fill")
                                    .imageScale(.small)
                                    .foregroundStyle(.secondary)
                                Text(appState.formattedDistance(fromMeters: meters))
                                     .font(.caption)
                                     .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        } else {
                            // No location value yet — display an action based on authorization
                            switch appState.locationManager.authorizationStatus {
                            case .notDetermined:
                                Button(action: { appState.locationManager.requestPermission() }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "location")
                                            .imageScale(.small)
                                        Text("Allow location")
                                            .font(.caption)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .padding(.top, 4)
                            case .restricted, .denied:
                                Button(action: {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        openURL(url)
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "gearshape.fill")
                                            .imageScale(.small)
                                        Text("Enable in Settings")
                                            .font(.caption)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .padding(.top, 4)
                            default:
                                Text("Location unknown").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .overlay(Rectangle().fill(Color.accentColor).frame(width: 4), alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
    }

    // Prominent seating-based Busy/Not busy indicator derived from student seating reports
    private var seatingIndicator: some View {
        let s = hall.seating?.lowercased() ?? ""
        let (label, color): (String, Color) = {
            if s.contains("plenty") || s.contains("some") { return ("Not busy", .green) }
            if s.contains("few") || s.contains("packed") { return ("Busy", .orange) }
            return ("No reports", .gray)
        }()

        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(label).font(.subheadline).fontWeight(.semibold)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
        }
    }

    // Compact open/closed label to show near the updated/hours text (Google Maps style)
    private var openClosedLabel: some View {
        let (text, color): (String, Color) = {
            switch hall.status {
            case .open: return ("Open", .green)
            case .busy: return ("Open", .orange)
            case .closed: return (hall.id == "brittain" ? "Temporarily Closed" : "Closed", .red)
            case .unknown: return ("Temporarily Closed", .red)
            }
        }()
        let hoursNote: String? = {
            if hall.status == .open {
                if let closes = hall.closesAt, !closes.isEmpty { return "‧ Closes \(closes)" }
            } else if hall.status == .closed {
                if let opens = hall.opensAt, !opens.isEmpty { return "‧ Opens \(opens)" }
            } else {
                if let closes = hall.closesAt, !closes.isEmpty { return "‧ Closes \(closes)" }
                else if let opens = hall.opensAt, !opens.isEmpty { return "‧ Opens \(opens)" }
            }
            return nil
        }()

        return HStack(spacing: 6) {
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            if let note = hoursNote {
                Text("\(note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
