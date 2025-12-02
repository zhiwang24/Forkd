//
//  WaitTimeInputView.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import SwiftUI
import UIKit

struct WaitTimeInputView: View {
    @EnvironmentObject private var appState: AppState
    let hall: DiningHall
    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    @State private var isSubmitting = false
    @State private var alertMessage: String? = nil
    @State private var showingAuth: Bool = false
    @State private var showOpenSettings: Bool = false
    @State private var pendingAfterPermission: Bool = false

    // Seating options
    private let seatingOptions: [String] = ["Plenty", "Some", "Few", "Packed"]
    @State private var selectedSeatingIndex: Int? = nil

    private let quick: [Int] = [1,2,3,4,5,8,10,15,20]

    // Keep grid columns as a separate computed property to simplify the view builder.
    private var seatingColumns: [GridItem] { [GridItem(.adaptive(minimum: 80), spacing: 8)] }
    private var hallIsClosed: Bool { appState.hallIsClosed(hall.id) }

    // Small helper to reduce expression complexity inside the view body.
    private func seatingButton(at idx: Int) -> AnyView {
        let label = seatingOptions[idx]
        let btn = Button(action: { selectedSeatingIndex = idx }) {
            Text(label)
                .font(.caption)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(selectedSeatingIndex == idx ? .accentColor : .gray)

        return AnyView(btn)
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationContent
            if showOpenSettings {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }
        }
    }

    // Extracted smaller view to reduce complexity in the main body and help the compiler
    private var navigationContent: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    currentCard
                    inputSection
                    seatingSection
                    submit
                    if hallIsClosed {
                        Text("This hall is closed right now. Come back later for updates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let msg = alertMessage {
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    tip
                }
                .padding()
            }
            .navigationTitle("Update Wait Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        }
        .sheet(isPresented: $showingAuth) {
            AuthView().environmentObject(appState)
        }
        .onReceive(appState.locationManager.$authorizationStatus) { status in
            // If the user granted permission and we have a pending intent from this view, continue automatically
            if pendingAfterPermission && (status == .authorizedWhenInUse || status == .authorizedAlways) {
                pendingAfterPermission = false
                // attempt the submission flow automatically
                Task { await performPendingSubmit() }
            }
        }
    }

     private var seatingSection: some View {
         VStack(alignment: .leading, spacing: 8) {
             Text("Seating availability")
                 .font(.subheadline).bold()
             // Use an adaptive grid so buttons wrap naturally on narrow screens instead of forcing an oversized row.
             LazyVGrid(columns: seatingColumns, alignment: .leading, spacing: 8) {
                 ForEach(seatingOptions.indices, id: \.self) { idx in
                     seatingButton(at: idx)
                 }
             }
             if let idx = selectedSeatingIndex {
                 Text("Selected: \(seatingOptions[idx])").font(.caption).foregroundStyle(.secondary)
             }
         }
     }

     private var currentCard: some View {
         VStack(alignment: .leading, spacing: 8) {
             HStack(spacing: 6) { Image(systemName: "clock").imageScale(.small).foregroundStyle(.secondary)
                 Text("Current estimated wait time").font(.footnote).foregroundStyle(.secondary) }
             Text(hall.waitTime).font(.title2).bold().foregroundStyle(Color.accentColor)
         }
         .card()
     }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Update dining hall status")
                .font(.subheadline).bold()
            HStack {
                ForEach(HallStatus.allCases, id: \.self) { status in
                    Button(status.rawValue.capitalized) {
                        appState.updateStatus(for: hall.id, to: status)
                    }
                    .buttonStyle(.bordered)
                    .tint(status == hall.status ? .accentColor : .gray)
                }
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How long did you actually wait?")
            HStack {
                TextField("5", text: $input)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Text("minutes").foregroundStyle(.secondary)
            }
            quickGrid
        }
    }

    // Extracted quick-select grid to reduce expression complexity inside `inputSection`.
    private var quickGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick select:")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(quick, id: \.self) { m in
                    quickButton(m)
                }
            }
        }
    }

    // Small helper for each quick-select button.
    private func quickButton(_ m: Int) -> some View {
        Button(action: { input = String(m) }) {
            Text("\(m) min")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(input == String(m) ? .accentColor : .gray)
    }

    private var submit: some View {
        Button(action: handleSubmit) {
            HStack { Image(systemName: isSubmitting ? "checkmark.circle" : "checkmark.circle")
                .rotationEffect(.degrees(isSubmitting ? 360 : 0))
                .animation(.linear(duration: isSubmitting ? 1 : 0), value: isSubmitting)
                Text(isSubmitting ? "Updating..." : "Update Wait Time") }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSubmitting || hallIsClosed || ((Int(input) ?? 0) <= 0 && selectedSeatingIndex == nil))
    }

    private func handleSubmit() {
        if hallIsClosed {
            alertMessage = "This hall is closed right now."
            return
        }
        // Require a signed-in & verified GT account before allowing updates
        guard appState.firebaseUser != nil, appState.isVerified else {
            alertMessage = "Please sign in with your @gatech.edu account and verify your email before submitting wait times."
            showingAuth = true
            return
        }
        let minutes = Int(input) ?? 0
        if minutes == 0 && selectedSeatingIndex == nil { return }
        if minutes < 0 || minutes > 60 { return }
        // Request a fresh location and check geofence before submitting.
        // If permission hasn't been requested, ask the user to allow it first.
        let authStatus = appState.locationManager.authorizationStatus
        if authStatus == .notDetermined {
            // record the pending intent so we can automatically continue when permission is granted
            let seating = selectedSeatingIndex.map { seatingOptions[$0] }
            appState.setPendingLocationIntent(.waitAndSeating(hallID: hall.id, minutes: minutes, seating: seating))
            pendingAfterPermission = true
            // trigger the system prompt
            appState.locationManager.requestPermission()
            alertMessage = "Please allow location access in the prompt; the app will continue automatically once permission is granted."
            return
        }
        if authStatus == .denied || authStatus == .restricted {
            alertMessage = "Location access is denied. Allow location access in Settings to validate submissions."
            showOpenSettings = true
            return
        }

        // Ask for a location update and wait briefly for the device to get a fix
        appState.locationManager.requestLocation()
        isSubmitting = true
        Task {
            // small pause to allow location manager to deliver a fix
            try? await Task.sleep(nanoseconds: 600_000_000)
            let geo = appState.checkGeofence(for: hall.id)
            if !geo.allowed {
                isSubmitting = false
                alertMessage = geo.message ?? "Your location could not be verified."
                if geo.message?.lowercased().contains("settings") == true { showOpenSettings = true }
                return
            }

            var success = true
            var message: String? = nil
            if minutes > 0 {
                let res = appState.updateWaitTime(for: hall.id, to: minutes)
                success = success && res.success
                if !res.success { message = res.message }
            }
            if let idx = selectedSeatingIndex {
                let seating = seatingOptions[idx]
                let res2 = appState.submitSeating(for: hall.id, seating: seating)
                success = success && res2.success
                if !res2.success { message = res2.message }
            }
            isSubmitting = false
            if success {
                dismiss()
            } else {
                alertMessage = message ?? "Failed to submit."
                if let msg = message, msg.lowercased().contains("verify") { showingAuth = true }
            }
        }
    }

    private func performPendingSubmit() async {
        // Called after permission is granted to continue the pending submission
        // Request a fresh location and then proceed
        appState.locationManager.requestLocation()
        isSubmitting = true
        try? await Task.sleep(nanoseconds: 600_000_000)
        let geo = appState.checkGeofence(for: hall.id)
        if !geo.allowed {
            isSubmitting = false
            alertMessage = geo.message ?? "Your location could not be verified."
            return
        }
        // Handle different pending intent variants
        if let intent = appState.pendingLocationIntent {
            switch intent {
            case .wait(let hallID, let minutes):
                let res = appState.updateWaitTime(for: hallID, to: minutes)
                isSubmitting = false
                if res.success { dismiss() } else { alertMessage = res.message ?? "Failed to submit." }
            case .seating(let hallID, let seating):
                let res = appState.submitSeating(for: hallID, seating: seating)
                isSubmitting = false
                if res.success { dismiss() } else { alertMessage = res.message ?? "Failed to submit." }
            case .waitAndSeating(let hallID, let minutes, let seating):
                var success = true
                var message: String? = nil
                if minutes > 0 {
                    let res1 = appState.updateWaitTime(for: hallID, to: minutes)
                    success = success && res1.success
                    if !res1.success { message = res1.message }
                }
                if let seat = seating {
                    let res2 = appState.submitSeating(for: hallID, seating: seat)
                    success = success && res2.success
                    if !res2.success { message = res2.message }
                }
                isSubmitting = false
                if success { dismiss() } else { alertMessage = message ?? "Failed to submit." }
            default:
                isSubmitting = false
            }
            // Clear pending intent stored in AppState
            appState.clearPendingLocationIntent()
        } else {
            isSubmitting = false
        }
    }

    private var tip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock").imageScale(.small).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Help other students!").font(.subheadline).bold()
                Text("Your input helps keep wait times accurate for everyone. Thanks for contributing!")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
