//
//  ContentView.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    ForEach(appState.halls) { hall in
                        HallRow(hall: hall) {
                            appState.selectedHall = hall
                            path.append(hall)
                        }
                    }
                    footer
                }
                .padding()
            }
            .navigationDestination(for: DiningHall.self) { hall in
                DiningHallDetailView(hall: hall, path: $path)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
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
}

struct HallRow: View {
    var hall: DiningHall
    var onTap: () -> Void

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
                        statusBadge
                    }
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2").imageScale(.small)
                            Text("\(hall.menuItems.count) items available").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Updated \(hall.lastUpdated)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(leadingWaitNumber)
                        .font(.title2).bold().foregroundStyle(Color.accentColor)
                    Text("min wait").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .overlay(Rectangle().fill(Color.accentColor).frame(width: 4), alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
    }

    private var leadingWaitNumber: String {
        // Extract the first number from e.g. "5-10 min"
        let comps = hall.waitTime.split(separator: " ").first ?? "0"
        let range = comps.split(separator: "-").first ?? comps
        return String(range)
    }

    private var statusBadge: some View {
        let text: String
        let color: Color
        switch hall.status {
        case .open: text = "Open"; color = .green
        case .busy: text = "Busy"; color = .yellow
        case .closed: text = "Closed"; color = .red
        case .unknown: text = "Unknown"; color = .gray
        }
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).bold()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}
