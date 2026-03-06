import Combine
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

@MainActor
private class HomeViewModel: ObservableObject {
    @Published var events: [Event] = []
    @Published var commentCounts: [String: Int] = [:]
    @Published var pendingProposalCounts: [String: Int] = [:]

    private let eventService = EventService()
    private var eventListener: ListenerRegistration?
    private var commentListeners: [String: ListenerRegistration] = [:]
    private var proposalListeners: [String: ListenerRegistration] = [:]

    func listenToEvents(in circleId: String) {
        stopListening()
        eventListener = eventService.listenToEvents(circleId: circleId) { [weak self] events in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let newIds = Set(events.compactMap(\.id))
                for id in Set(self.commentListeners.keys).subtracting(newIds) {
                    self.commentListeners[id]?.remove()
                    self.commentListeners.removeValue(forKey: id)
                    self.proposalListeners[id]?.remove()
                    self.proposalListeners.removeValue(forKey: id)
                }
                self.events = events
                for event in events {
                    guard let id = event.id else { continue }
                    self.listenToCommentCount(eventId: id)
                    self.listenToPendingProposalCount(eventId: id)
                }
            }
        }
    }

    func stopListening() {
        eventListener?.remove()
        eventListener = nil
        commentListeners.values.forEach { $0.remove() }
        commentListeners.removeAll()
        proposalListeners.values.forEach { $0.remove() }
        proposalListeners.removeAll()
    }

    func updateParticipantStatus(eventId: String, userId: String, status: ParticipantStatus) {
        Task {
            try? await eventService.updateParticipantStatus(
                eventId: eventId, userId: userId, status: status)
        }
    }

    private func listenToCommentCount(eventId: String) {
        guard commentListeners[eventId] == nil else { return }
        commentListeners[eventId] = eventService.listenToComments(eventId: eventId) {
            [weak self] comments in
            Task { @MainActor [weak self] in
                self?.commentCounts[eventId] = comments.count
            }
        }
    }

    private func listenToPendingProposalCount(eventId: String) {
        guard proposalListeners[eventId] == nil else { return }
        proposalListeners[eventId] = eventService.listenToProposals(eventId: eventId) {
            [weak self] proposals in
            Task { @MainActor [weak self] in
                self?.pendingProposalCounts[eventId] =
                    proposals.filter { $0.status == .pending }.count
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var navigationManager: NavigationManager
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack(path: $navigationManager.homePath) {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemGray6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                content
            }
            .navigationTitle(appState.activeCircle?.name ?? "Events")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .eventDetail(let event):
                    EventDetailView(event: event)
                }
            }
        }
        .onChange(of: appState.activeCircle?.id) { _, circleId in
            if let id = circleId {
                viewModel.listenToEvents(in: id)
            } else {
                viewModel.stopListening()
            }
        }
        .onAppear {
            if let id = appState.activeCircle?.id {
                viewModel.listenToEvents(in: id)
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.activeCircle == nil {
            ContentUnavailableView(
                "No FriendCircle Selected",
                systemImage: "person.3",
                description: Text("Join or create a circle from the menu to see events.")
            )
        } else if viewModel.events.isEmpty {
            ContentUnavailableView(
                "No Events Yet",
                systemImage: "calendar.badge.plus",
                description: Text("Tap + to create the first event.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.events) { event in
                        NavigationLink(value: HomeDestination.eventDetail(event)) {
                            EventCard(
                                event: event,
                                commentCount: viewModel.commentCounts[event.id ?? ""] ?? 0,
                                pendingProposalCount: viewModel.pendingProposalCounts[
                                    event.id ?? ""] ?? 0,
                                currentUserId: appState.authService.currentUser?.uid ?? "",
                                onStatusChange: { status in
                                    guard let eventId = event.id,
                                        let userId = appState.authService.currentUser?.uid
                                    else { return }
                                    viewModel.updateParticipantStatus(
                                        eventId: eventId, userId: userId, status: status)
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .refreshable {
                if let id = appState.activeCircle?.id {
                    viewModel.listenToEvents(in: id)
                    // Add a tiny delay so the spinner actually shows instead of instantly disappearing
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
    }
}
