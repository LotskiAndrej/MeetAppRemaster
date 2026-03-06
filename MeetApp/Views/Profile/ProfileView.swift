import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var errorMessage: String?
    @State private var isEditing = false
    @State private var editFirstName = ""
    @State private var editLastName = ""
    @State private var isSaving = false

    private let userService = UserService()

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    VStack(spacing: 12) {
                        ZStack {
                            SwiftUI.Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 80, height: 80)
                            Text(initials)
                                .font(.title.bold())
                                .foregroundStyle(.primary)
                        }

                        if isEditing {
                            VStack(spacing: 8) {
                                TextField("First name", text: $editFirstName)
                                    .textContentType(.givenName)
                                    .multilineTextAlignment(.center)
                                    .font(.title2.bold())
                                    .textFieldStyle(.roundedBorder)
                                TextField("Last name", text: $editLastName)
                                    .textContentType(.familyName)
                                    .multilineTextAlignment(.center)
                                    .font(.title2.bold())
                                    .textFieldStyle(.roundedBorder)
                            }
                            .padding(.horizontal)
                        } else if let profile = appState.currentUser {
                            Text(profile.fullName)
                                .font(.title2.bold())
                            Text(appState.authService.currentUser?.email ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    if !isEditing {
                        Button(role: .destructive) {
                            signOut()
                        } label: {
                            Text("Sign Out")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Profile")
            .toolbar {
                if let profile = appState.currentUser {
                    if isEditing {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                isEditing = false
                                errorMessage = nil
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { saveName(profile: profile) }
                                .fontWeight(.semibold)
                                .disabled(
                                    editFirstName.trimmingCharacters(in: .whitespaces).isEmpty
                                    || editLastName.trimmingCharacters(in: .whitespaces).isEmpty
                                    || isSaving
                                )
                        }
                    } else {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Edit") {
                                editFirstName = profile.firstName
                                editLastName = profile.lastName
                                isEditing = true
                            }
                        }
                    }
                }
            }
        }
    }

    private var initials: String {
        guard let profile = appState.currentUser else { return "?" }
        let f = profile.firstName.prefix(1).uppercased()
        let l = profile.lastName.prefix(1).uppercased()
        return "\(f)\(l)"
    }

    private func signOut() {
        do {
            try appState.authService.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveName(profile: User) {
        isSaving = true
        var updated = profile
        updated.firstName = editFirstName.trimmingCharacters(in: .whitespaces)
        updated.lastName = editLastName.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                try userService.updateUser(updated)
                await MainActor.run {
                    isEditing = false
                    isSaving = false
                    errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}
