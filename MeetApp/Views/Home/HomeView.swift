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

    var upcomingEvents: [Event] {
        events.filter { $0.date.dateValue() >= Date() }
              .sorted { $0.date.dateValue() < $1.date.dateValue() }
    }

    var pastEvents: [Event] {
        events.filter { $0.date.dateValue() < Date() }
              .sorted { $0.date.dateValue() > $1.date.dateValue() }
    }

    var upcomingEventsByDay: [(title: String, events: [Event])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: upcomingEvents) {
            cal.startOfDay(for: $0.date.dateValue())
        }
        return grouped.keys.sorted().map { day in
            (title: daySectionTitle(for: day), events: grouped[day]!
                .sorted { $0.date.dateValue() < $1.date.dateValue() })
        }
    }

    private func daySectionTitle(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInTomorrow(date)  { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "d MMMM"
        return f.string(from: date)
    }

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

    func deleteEvent(_ event: Event) {
        guard let eventId = event.id else { return }
        Task { try? await eventService.deleteEvent(eventId: eventId) }
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
    @AppStorage("pastEventsSectionExpanded") private var pastSectionExpanded = false
    @State private var showCreateEvent = false
    @State private var showMembers = false
    @State private var eventToDelete: Event?

    private var currentUserId: String { appState.authService.currentUser?.uid ?? "" }

    var body: some View {
        NavigationStack(path: $navigationManager.homePath) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    LinearGradient(
                        colors: [Color(.systemBackground), Color(.systemGray6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }
                .navigationTitle(appState.activeCircle?.name ?? "Events")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    if appState.activeCircle != nil {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { showMembers = true } label: {
                                Image(systemName: "person.2")
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showCreateEvent = true } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                }
                .navigationDestination(for: HomeDestination.self) { destination in
                    switch destination {
                    case .eventDetail(let event):
                        EventDetailView(event: event)
                    }
                }
                .alert("Delete Event", isPresented: Binding(
                    get: { eventToDelete != nil },
                    set: { if !$0 { eventToDelete = nil } }
                )) {
                    Button("Delete", role: .destructive) {
                        if let event = eventToDelete {
                            viewModel.deleteEvent(event)
                        }
                        eventToDelete = nil
                    }
                    Button("Cancel", role: .cancel) { eventToDelete = nil }
                } message: {
                    if let event = eventToDelete {
                        Text("Delete the event at \(event.place)? Going attendees will be notified.")
                    }
                }
        }
        .sheet(isPresented: $showCreateEvent) {
            CreateEventView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showMembers) {
            if let circle = appState.activeCircle {
                CircleMembersSheet(
                    circle: circle,
                    currentUserId: currentUserId
                )
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
            List {
                ForEach(viewModel.upcomingEventsByDay, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.events) { event in
                            eventRow(for: event)
                        }
                    }
                }

                if !viewModel.pastEvents.isEmpty {
                    Section {
                        if pastSectionExpanded {
                            ForEach(viewModel.pastEvents) { event in
                                eventRow(for: event)
                            }
                        }
                    } header: {
                        Button {
                            withAnimation { pastSectionExpanded.toggle() }
                        } label: {
                            HStack {
                                Text("Past Events")
                                    .font(.footnote)
                                    .fontWeight(.semibold)
                                    .textCase(nil)
                                Spacer()
                                Image(systemName: pastSectionExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func eventRow(for event: Event) -> some View {
        let isOrganizer = event.organizerId == currentUserId
        Button {
            navigationManager.homePath.append(HomeDestination.eventDetail(event))
        } label: {
            EventCard(
                event: event,
                commentCount: viewModel.commentCounts[event.id ?? ""] ?? 0,
                pendingProposalCount: viewModel.pendingProposalCounts[event.id ?? ""] ?? 0,
                currentUserId: currentUserId,
                isOrganizer: isOrganizer,
                onStatusChange: { status in
                    guard let eventId = event.id else { return }
                    viewModel.updateParticipantStatus(
                        eventId: eventId, userId: currentUserId, status: status)
                },
                onDelete: isOrganizer ? { eventToDelete = event } : nil
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isOrganizer {
                Button(role: .destructive) {
                    eventToDelete = event
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
    }
}

// MARK: - Circle Members Sheet

private struct CircleMembersSheet: View {
    let circle: FriendCircle
    let currentUserId: String
    @Environment(\.dismiss) private var dismiss
    @State private var members: [User] = []
    @State private var isLoading = true
    @State private var userToKick: User?

    private let userService = UserService()
    private let circleService = CircleService()

    private var isAdmin: Bool { circle.adminId == currentUserId }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(members) { member in
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(member.fullName)
                            Spacer()
                            if member.id == circle.adminId {
                                Text("Admin")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if isAdmin && member.id != currentUserId && member.id != circle.adminId {
                                Button(role: .destructive) {
                                    userToKick = member
                                } label: {
                                    Label("Remove", systemImage: "person.badge.minus")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Members (\(circle.memberIds.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Remove Member", isPresented: Binding(
                get: { userToKick != nil },
                set: { if !$0 { userToKick = nil } }
            )) {
                Button("Remove", role: .destructive) {
                    guard let user = userToKick, let circleId = circle.id, let uid = user.id else {
                        return
                    }
                    Task { try? await circleService.kickMember(circleId: circleId, userId: uid) }
                    userToKick = nil
                }
                Button("Cancel", role: .cancel) { userToKick = nil }
            } message: {
                if let user = userToKick {
                    Text("Remove \(user.fullName) from \(circle.name)?")
                }
            }
            .task { await loadMembers() }
        }
    }

    private func loadMembers() async {
        isLoading = true
        var loaded: [User] = []
        for uid in circle.memberIds {
            if let user = try? await userService.fetchUser(uid: uid) {
                loaded.append(user)
            }
        }
        loaded.sort {
            if $0.id == circle.adminId { return true }
            if $1.id == circle.adminId { return false }
            return $0.fullName < $1.fullName
        }
        members = loaded
        isLoading = false
    }
}
