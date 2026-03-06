import FirebaseAuth
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tabManager: TabManager
    @State private var showCreateCircle = false
    @State private var showJoinCircle = false
    @State private var circleToDelete: FriendCircle?
    @State private var circleToLeave: FriendCircle?

    private var currentUserId: String { appState.authService.currentUser?.uid ?? "" }

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
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if circle.adminId == currentUserId {
                                        Button(role: .destructive) {
                                            circleToDelete = circle
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    } else {
                                        Button(role: .destructive) {
                                            circleToLeave = circle
                                        } label: {
                                            Label("Leave", systemImage: "arrow.right.square")
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
            .alert("Delete Circle", isPresented: Binding(
                get: { circleToDelete != nil },
                set: { if !$0 { circleToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let circle = circleToDelete, let circleId = circle.id {
                        Task { try? await CircleService().deleteCircle(circleId: circleId, memberIds: circle.memberIds) }
                    }
                    circleToDelete = nil
                }
                Button("Cancel", role: .cancel) { circleToDelete = nil }
            } message: {
                if let circle = circleToDelete {
                    Text("Delete \"\(circle.name)\"? This will remove the circle for all members and cannot be undone.")
                }
            }
            .alert("Leave Circle", isPresented: Binding(
                get: { circleToLeave != nil },
                set: { if !$0 { circleToLeave = nil } }
            )) {
                Button("Leave", role: .destructive) {
                    if let circle = circleToLeave, let circleId = circle.id {
                        Task { try? await CircleService().kickMember(circleId: circleId, userId: currentUserId) }
                    }
                    circleToLeave = nil
                }
                Button("Cancel", role: .cancel) { circleToLeave = nil }
            } message: {
                if let circle = circleToLeave {
                    Text("Leave \"\(circle.name)\"? You'll need the invite code to rejoin.")
                }
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
