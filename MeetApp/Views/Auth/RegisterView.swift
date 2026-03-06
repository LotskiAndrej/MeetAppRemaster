import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@") &&
        password.count >= 6 &&
        password == confirmPassword
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 40)

                    Text("Create Account")
                        .font(.largeTitle.bold())

                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            TextField("First Name", text: $firstName)
                                .textContentType(.givenName)
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                            TextField("Last Name", text: $lastName)
                                .textContentType(.familyName)
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }

                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                        SecureField("Password (min. 6 characters)", text: $password)
                            .textContentType(.newPassword)
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                        SecureField("Confirm Password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                        if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                            Text("Passwords do not match.")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        Button {
                            Task { await register() }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Create Account")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isValid ? Color.accentColor : Color.gray.opacity(0.4))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(!isValid || isLoading)
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
        }
        .navigationTitle("Register")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func register() async {
        isLoading = true
        errorMessage = nil
        do {
            let uid = try await appState.authService.signUp(email: email, password: password)
            var newUser = User(firstName: firstName.trimmingCharacters(in: .whitespaces),
                               lastName: lastName.trimmingCharacters(in: .whitespaces),
                               circleIds: [])
            newUser.id = uid
            try UserService().createUser(newUser)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

