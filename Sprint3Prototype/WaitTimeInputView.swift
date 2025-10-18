//
//  WaitTimeInputView.swift
//  Sprint3Prototype
//
//  Created by Zhi on 10/17/25.
//

import SwiftUI

struct WaitTimeInputView: View {
    @EnvironmentObject private var appState: AppState
    let hall: DiningHall
    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    @State private var isSubmitting = false

    private let quick: [Int] = [1,2,3,4,5,8,10,15,20]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    currentCard
                    inputSection
                    submit
                    tip
                }
                .padding()
            }
            .navigationTitle("Update Wait Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick select:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(quick, id: \.self) { m in
                        Button("\(m) min") { input = String(m) }
                            .buttonStyle(BorderedButtonStyle())
                            .tint(input == String(m) ? .accentColor : .gray)

                    }
                }
            }
        }
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
        .disabled(isSubmitting || (Int(input) ?? 0) <= 0)
    }

    private func handleSubmit() {
        guard let minutes = Int(input), minutes > 0, minutes <= 60 else { return }
        isSubmitting = true
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            appState.updateWaitTime(for: hall.id, to: minutes)
            isSubmitting = false
            dismiss()
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

