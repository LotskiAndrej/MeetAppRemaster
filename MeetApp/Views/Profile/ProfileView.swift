import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var errorMessage: String?

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

                        if let profile = appState.currentUser {
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

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Profile")
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
}
