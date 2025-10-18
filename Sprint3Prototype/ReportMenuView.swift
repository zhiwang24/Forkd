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

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Which item is wrong or missing?")) {
                    TextField("Item name (optional)", text: $itemName)
                }

                Section(header: Text("Details")) {
                    TextEditor(text: $details)
                        .frame(minHeight: 120)
                }

                Section(header: Text("Your contact (optional)")) {
                    TextField("Name or email (optional)", text: $reporter)
                }

                if let msg = alertMessage {
                    Section {
                        Text(msg).foregroundColor(.red)
                    }
                }

                Section {
                    Button(action: submitReport) {
                        if isSubmitting {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else {
                            Text("Submit Report")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isSubmitting || details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
        ReportMenuView(hall: DiningHall(id: "1", name: "North Ave Dining", waitTime: "5-10 min", status: .open, lastUpdated: "2m ago", menuItems: [], verifiedCount: 142))
            .environmentObject(AppState())
    }
}
