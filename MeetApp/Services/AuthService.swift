@preconcurrency import Foundation
import FirebaseAuth
import Combine

@MainActor
class AuthService: ObservableObject {
    @Published var currentUser: FirebaseAuth.User?
    @Published var isInitializing = true

    private var authStateListener: AuthStateDidChangeListenerHandle?

    init() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                self?.currentUser = user
                self?.isInitializing = false
            }
        }
    }

    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    /// Creates a new Firebase Auth account and returns the new user's UID.
    func signUp(email: String, password: String) async throws -> String {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        return result.user.uid
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }
}
