//
//  BugReportView.swift
//  Sprint3Prototype
//
//  Created by Ayane on 10/18/25.
//

import SwiftUI
import FirebaseFirestore

struct BugReportView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var details: String = ""
    @State private var reporter: String = ""
    @State private var isSubmitting: Bool = false
    @State private var alertMessage: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "bug.fill")
                            Text("Short title").font(.subheadline).bold()
                        }
                        TextField("What happened? (e.g. Crash on launch)", text: $title)
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
                            Text(isSubmitting ? "Submitting..." : "Submit Bug Report")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(isSubmitting || details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "ladybug.fill").imageScale(.small).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Report bugs you find").font(.subheadline).bold()
                            Text("Thanks — we review bug reports and prioritize fixes. Please include steps to reproduce if possible.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Report a Bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submitReport() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            alertMessage = "Please provide a short title for the bug."
            return
        }
        guard !trimmedDetails.isEmpty else {
            alertMessage = "Please provide details about the bug."
            return
        }

        isSubmitting = true
        alertMessage = nil

        let db = Firestore.firestore()
        var data: [String: Any] = [
            "title": trimmedTitle,
            "details": trimmedDetails,
            "timestamp": Timestamp(date: Date()),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]
        if !reporter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["reporter"] = reporter.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        db.collection("bug_reports").addDocument(data: data) { error in
            DispatchQueue.main.async {
                isSubmitting = false
                if let error = error {
                    alertMessage = "Failed to submit bug report: \(error.localizedDescription)"
                } else {
                    dismiss()
                }
            }
        }
    }
}

struct BugReportView_Previews: PreviewProvider {
    static var previews: some View {
        BugReportView().environmentObject(AppState())
    }
}
