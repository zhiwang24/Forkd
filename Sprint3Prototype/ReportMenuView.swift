//
//  ReportMenuView.swift
//  Sprint3Prototype
//
//  Created by Ayane on 10/18/25.
//

import SwiftUI
import FirebaseFirestore

struct ReportMenuView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let hall: DiningHall

    @State private var itemName: String = ""
    @State private var details: String = ""
    @State private var reporter: String = ""
    @State private var isSubmitting: Bool = false
    @State private var alertMessage: String? = nil
    @State private var showingAuth: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "tag")
                            Text("Which item is wrong or missing?")
                                .font(.subheadline).bold()
                        }
                        TextField("Item name (optional)", text: $itemName)
                            .textFieldStyle(.roundedBorder)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "text.bubble")
                            Text("Details").font(.subheadline).bold()
                        }
                        TextEditor(text: $details)
                            .frame(minHeight: 140)
                            .padding(6)
                            .background(Color.card)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle")
                            Text("Your contact (optional)").font(.subheadline).bold()
                        }
                        TextField("GT email (optional)", text: $reporter)
                            .textFieldStyle(.roundedBorder)
                    }
                    .card()

                    if let msg = alertMessage {
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Button(action: submitReport) {
                        HStack {
                            if isSubmitting { ProgressView().progressViewStyle(CircularProgressViewStyle()) }
                            else { Image(systemName: "paperplane.fill") }
                            Text(isSubmitting ? "Submitting..." : "Submit Report")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(isSubmitting || details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .sheet(isPresented: $showingAuth) {
                        AuthView()
                            .environmentObject(appState)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.bubble").imageScale(.small).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Report issues you find").font(.subheadline).bold()
                            Text("Thanks for helping keep menus accurate — we review reports and update menus accordingly.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Report Menu Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submitReport() {
        guard let _ = appState.firebaseUser, appState.isVerified else {
            alertMessage = "Please sign in with your @gatech.edu account and verify your email before submitting reports."
            showingAuth = true
            return
        }
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDetails.isEmpty else {
            alertMessage = "Please provide details about the issue."
            return
        }

        isSubmitting = true
        alertMessage = nil

        let db = Firestore.firestore()
        var data: [String: Any] = [
            "hallId": hall.id,
            "hallName": hall.name,
            "details": trimmedDetails,
            "timestamp": Timestamp(date: Date())
        ]
        if !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["itemName"] = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !reporter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["reporter"] = reporter.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        db.collection("menu_reports").addDocument(data: data) { error in
            DispatchQueue.main.async {
                isSubmitting = false
                if let error = error {
                    alertMessage = "Failed to submit report: \(error.localizedDescription)"
                } else {
                    dismiss()
                }
            }
        }
    }
}

struct ReportMenuView_Previews: PreviewProvider {
    static var previews: some View {
        ReportMenuView(hall: DiningHall(id: "1", name: "North Ave Dining", waitTime: "5-10 min", status: .open, lastUpdatedAt: Date().addingTimeInterval(-120).timeIntervalSince1970, menuItems: [], verifiedCount: 142))
            .environmentObject(AppState())
    }
}
