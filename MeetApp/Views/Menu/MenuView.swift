import FirebaseAuth
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tabManager: TabManager
    @State private var showCreateCircle = false
    @State private var showJoinCircle = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                List {
                    Section("Your Circles") {
                        if appState.circles.isEmpty {
                            Text("No circles yet. Create or join one below.")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        } else {
                            ForEach(appState.circles) { circle in
                                Button {
                                    appState.setActiveCircle(circle)
                                    tabManager.selectedTab = 0
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(circle.name)
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            Text("Code: \(circle.inviteCode)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if appState.activeCircle?.id == circle.id {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Section("Actions") {
                        Button {
                            showCreateCircle = true
                        } label: {
                            Label("Create Circle", systemImage: "plus.circle")
                        }

                        Button {
                            showJoinCircle = true
                        } label: {
                            Label("Join Circle", systemImage: "person.badge.plus")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Menu")
            .sheet(isPresented: $showCreateCircle) {
                CreateCircleSheet()
            }
            .sheet(isPresented: $showJoinCircle) {
                JoinCircleSheet()
            }
        }
    }
}

// MARK: - Create FriendCircle Sheet

private struct CreateCircleSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("FriendCircle Name") {
                    TextField("e.g. Weekend Squad", text: $name)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Create FriendCircle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(!isValid || isLoading)
                }
            }
        }
    }

    private func create() async {
        guard let uid = appState.authService.currentUser?.uid else { return }
        isLoading = true
        errorMessage = nil
        do {
            _ = try await CircleService().createCircle(
                name: name.trimmingCharacters(in: .whitespaces),
                adminId: uid
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Join FriendCircle Sheet

private struct JoinCircleSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    private var isValid: Bool {
        inviteCode.trimmingCharacters(in: .whitespaces).count == 6
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite Code") {
                    TextField("6-character code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Join FriendCircle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        Task { await join() }
                    }
                    .disabled(!isValid || isLoading)
                }
            }
        }
    }

    private func join() async {
        guard let uid = appState.authService.currentUser?.uid else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await CircleService().joinCircle(
                inviteCode: inviteCode.trimmingCharacters(in: .whitespaces).uppercased(),
                userId: uid
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
