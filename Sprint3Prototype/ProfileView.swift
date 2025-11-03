//
//  ProfileView.swift
//  Sprint3Prototype
//
//  Created by Ayane on 10/18/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView().padding()
                } else {
                    VStack(spacing: 12) {
                        avatar
                        VStack(alignment: .center, spacing: 4) {
                            Text("\(firstName) \(lastName)").font(.title3).bold()
                            HStack(spacing: 8) {
                                Text(email).font(.subheadline).foregroundStyle(.secondary)
                                if appState.isVerified {
                                    Label("Verified", systemImage: "checkmark.seal.fill")
                                        .font(.caption).foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    .padding()

                    // Units preference (Metric / Imperial)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Units").font(.subheadline).bold()
                        Picker("", selection: $appState.prefersMetric) {
                            Text("Imperial").tag(false)
                            Text("Metric").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding([.leading, .trailing])

                    if let msg = errorMessage {
                        Text(msg).foregroundColor(.red).font(.caption).padding(.horizontal)
                    }

                    Button(role: .destructive) {
                        appState.signOut()
                        dismiss()
                    } label: {
                        Text("Sign Out")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear(perform: loadProfile)
        }
    }

    private var avatar: some View {
        let initials = (firstName.first.map { String($0) } ?? "") + (lastName.first.map { String($0) } ?? "")
        return ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 88, height: 88)
            Text(initials.isEmpty ? "Me" : initials)
                .font(.title2).bold()
        }
    }

    private func loadProfile() {
        guard let user = appState.firebaseUser ?? Auth.auth().currentUser else {
            // no user, clear and show sign-in
            firstName = ""
            lastName = ""
            email = ""
            isLoading = false
            return
        }

        email = user.email ?? ""

        // Try to load Firestore profile (users/{uid}) if present
        let db = Firestore.firestore()
        db.collection("users").document(user.uid).getDocument { snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Failed to load profile: \(error.localizedDescription)"
                    // fallback to displayable info
                    self.firstName = user.displayName?.split(separator: " ").first.map { String($0) } ?? ""
                    self.lastName = user.displayName?.split(separator: " ").dropFirst().first.map { String($0) } ?? ""
                } else if let data = snapshot?.data() {
                    self.firstName = (data["firstName"] as? String) ?? ""
                    self.lastName = (data["lastName"] as? String) ?? ""
                } else {
                    // no document - fallback
                    self.firstName = user.displayName?.split(separator: " ").first.map { String($0) } ?? ""
                    self.lastName = user.displayName?.split(separator: " ").dropFirst().first.map { String($0) } ?? ""
                }
                self.isLoading = false
            }
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView().environmentObject(AppState())
    }
}
