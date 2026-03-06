import Combine
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

// MARK: - Helpers

private func relativeTimeString(from date: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 { return "less than a minute ago" }
    let minutes = seconds / 60
    if minutes == 1 { return "1 minute ago" }
    if minutes < 60 { return "\(minutes) minutes ago" }
    let hours = minutes / 60
    if hours == 1 { return "1 hour ago" }
    if hours < 24 { return "\(hours) hours ago" }
    let days = hours / 24
    if days == 1 { return "yesterday" }
    if days < 7 { return "\(days) days ago" }
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f.string(from: date)
}

// MARK: - ViewModel

@MainActor
private class EventDetailViewModel: ObservableObject {
    @Published var event: Event
    @Published var comments: [Comment] = []
    @Published var proposals: [Proposal] = []
    @Published var commentText = ""
    @Published var isSubmittingComment = false
    @Published var commentAuthors: [String: User] = [:]
    @Published var attendees: [User] = []
    @Published var notGoingAttendees: [User] = []

    private let eventService = EventService()
    private let userService = UserService()
    private var eventListener: ListenerRegistration?
    private var commentsListener: ListenerRegistration?
    private var proposalsListener: ListenerRegistration?

    init(event: Event) {
        self.event = event
    }

    func startListening() {
        guard let eventId = event.id else { return }
        eventListener = eventService.listenToEvent(eventId: eventId) { [weak self] updatedEvent in
            Task { @MainActor [weak self] in
                guard let self, let updatedEvent else { return }
                self.event = updatedEvent
                self.loadAttendees()
            }
        }
        commentsListener = eventService.listenToComments(eventId: eventId) { [weak self] comments in
            Task { @MainActor [weak self] in
                self?.comments = comments
                self?.fetchCommentAuthors(for: comments)
            }
        }
        proposalsListener = eventService.listenToProposals(eventId: eventId) {
            [weak self] proposals in
            Task { @MainActor [weak self] in self?.proposals = proposals }
        }
        loadAttendees()
    }

    private func fetchCommentAuthors(for comments: [Comment]) {
        let userIds = Set(comments.map(\.userId))
        for uid in userIds {
            if commentAuthors[uid] == nil {
                Task {
                    if let user = try? await userService.fetchUser(uid: uid) {
                        await MainActor.run { self.commentAuthors[uid] = user }
                    }
                }
            }
        }
    }

    func loadAttendees() {
        let goingIds = event.participants.filter { $0.value == .going }.map(\.key)
        let notGoingIds = event.participants.filter { $0.value == .notGoing }.map(\.key)

        for uid in goingIds {
            if !attendees.contains(where: { $0.id == uid }) {
                Task {
                    if let user = try? await userService.fetchUser(uid: uid) {
                        await MainActor.run {
                            if !self.attendees.contains(where: { $0.id == uid }) {
                                self.attendees.append(user)
                            }
                        }
                    }
                }
            }
        }
        attendees.removeAll { id in
            guard let uid = id.id else { return true }
            return !goingIds.contains(uid)
        }

        for uid in notGoingIds {
            if !notGoingAttendees.contains(where: { $0.id == uid }) {
                Task {
                    if let user = try? await userService.fetchUser(uid: uid) {
                        await MainActor.run {
                            if !self.notGoingAttendees.contains(where: { $0.id == uid }) {
                                self.notGoingAttendees.append(user)
                            }
                        }
                    }
                }
            }
        }
        notGoingAttendees.removeAll { id in
            guard let uid = id.id else { return true }
            return !notGoingIds.contains(uid)
        }
    }

    func stopListening() {
        eventListener?.remove()
        commentsListener?.remove()
        proposalsListener?.remove()
        eventListener = nil
        commentsListener = nil
        proposalsListener = nil
    }

    func submitComment(userId: String) {
        let trimmed = commentText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let eventId = event.id else { return }
        isSubmittingComment = true
        let comment = Comment(userId: userId, text: trimmed, createdAt: Timestamp(date: Date()))
        try? eventService.addComment(comment, to: eventId)
        commentText = ""
        isSubmittingComment = false
    }

    func deleteComment(_ comment: Comment) {
        guard let eventId = event.id, let commentId = comment.id else { return }
        Task { try? await eventService.deleteComment(eventId: eventId, commentId: commentId) }
    }

    func vote(on proposal: Proposal, userId: String, isUpvote: Bool) {
        guard let eventId = event.id, let proposalId = proposal.id else { return }
        let alreadyVoted = isUpvote ? proposal.upvotes.contains(userId) : proposal.downvotes.contains(userId)
        Task {
            if alreadyVoted {
                try? await eventService.removeVote(eventId: eventId, proposalId: proposalId, userId: userId)
            } else {
                try? await eventService.voteOnProposal(
                    eventId: eventId, proposalId: proposalId, userId: userId, isUpvote: isUpvote)
            }
        }
    }

    func accept(proposal: Proposal) {
        guard let eventId = event.id else { return }
        Task {
            try? await eventService.acceptProposal(eventId: eventId, proposal: proposal)
            if let place = proposal.proposedPlace { event.place = place }
            if let date = proposal.proposedDate { event.date = date }
        }
    }

    func reject(proposal: Proposal) {
        guard let eventId = event.id, let proposalId = proposal.id else { return }
        Task {
            try? await eventService.rejectProposal(eventId: eventId, proposalId: proposalId)
        }
    }

    func updateParticipantStatus(userId: String, status: ParticipantStatus) {
        guard let eventId = event.id else { return }
        event.participants[userId] = status
        loadAttendees()
        Task {
            try? await eventService.updateParticipantStatus(
                eventId: eventId, userId: userId, status: status)
        }
    }

    func addProposal(proposerId: String, proposedPlace: String?, proposedDate: Date?) {
        guard let eventId = event.id else { return }
        let proposal = Proposal(
            proposerId: proposerId,
            proposedPlace: proposedPlace,
            proposedDate: proposedDate.map { Timestamp(date: $0) },
            upvotes: [], downvotes: [],
            status: .pending,
            createdAt: Timestamp(date: Date())
        )
        try? eventService.addProposal(proposal, to: eventId)
    }

    func updateEvent(place: String, date: Date) {
        guard let eventId = event.id else { return }
        let newTimestamp = Timestamp(date: date)
        event.place = place
        event.date = newTimestamp
        Task { try? await eventService.updateEvent(eventId: eventId, place: place, date: newTimestamp) }
    }
}

// MARK: - EventDetailView

struct EventDetailView: View {
    @StateObject private var viewModel: EventDetailViewModel
    @EnvironmentObject private var appState: AppState
    @State private var showProposeSheet = false
    @State private var showEditSheet = false
    @FocusState private var isCommentFocused: Bool

    init(event: Event) {
        _viewModel = StateObject(wrappedValue: EventDetailViewModel(event: event))
    }

    private var currentUserId: String { appState.authService.currentUser?.uid ?? "" }
    private var isOrganizer: Bool { currentUserId == viewModel.event.organizerId }
    private var isPast: Bool { viewModel.event.date.dateValue() < Date() }

    var body: some View {
        List {
                eventHeaderCard
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))

                rsvpCard
                    .buttonStyle(.borderless)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))

                if !viewModel.attendees.isEmpty || !viewModel.notGoingAttendees.isEmpty {
                    Section {
                        ForEach(viewModel.attendees) { user in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(user.fullName)
                                    .font(.subheadline)
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Color.primary.opacity(0.08))
                        }
                        ForEach(viewModel.notGoingAttendees) { user in
                            HStack(spacing: 12) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red.opacity(0.5))
                                Text(user.fullName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Color.primary.opacity(0.08))
                        }
                    } header: {
                        HStack(spacing: 12) {
                            if !viewModel.attendees.isEmpty {
                                Label("Going (\(viewModel.attendees.count))", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            if !viewModel.notGoingAttendees.isEmpty {
                                Label("Not Going (\(viewModel.notGoingAttendees.count))", systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                    }
                    .listSectionSeparator(.hidden)
                }

                Section {
                    if viewModel.comments.isEmpty {
                        Text("No comments yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(viewModel.comments) { comment in
                            CommentRow(
                                comment: comment,
                                author: viewModel.commentAuthors[comment.userId]
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if comment.userId == currentUserId {
                                    Button(role: .destructive) {
                                        viewModel.deleteComment(comment)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Color.primary.opacity(0.08))
                        }
                    }

                    commentInputRow
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Comments")
                        .font(.headline)
                        .textCase(nil)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listSectionSeparator(.hidden)

                if !viewModel.proposals.isEmpty {
                    Section {
                        ForEach(viewModel.proposals) { proposal in
                            ProposalRow(
                                proposal: proposal,
                                currentUserId: currentUserId,
                                isOrganizer: isOrganizer,
                                isPast: isPast,
                                onVote: { isUpvote in
                                    viewModel.vote(on: proposal, userId: currentUserId, isUpvote: isUpvote)
                                },
                                onAccept: { viewModel.accept(proposal: proposal) },
                                onDeny: { viewModel.reject(proposal: proposal) }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    } header: {
                        Text("Proposals")
                            .font(.headline)
                            .textCase(nil)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .listSectionSeparator(.hidden)
                }
            }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.systemGray6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle(viewModel.event.place)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isCommentFocused = false }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showProposeSheet = true
                } label: {
                    Image(systemName: "text.badge.plus")
                }
                if isOrganizer {
                    Button {
                        showEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $showProposeSheet) {
            ProposeChangeView { proposedPlace, proposedDate in
                viewModel.addProposal(
                    proposerId: currentUserId,
                    proposedPlace: proposedPlace,
                    proposedDate: proposedDate
                )
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditEventView(event: viewModel.event) { place, date in
                viewModel.updateEvent(place: place, date: date)
            }
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
    }

    // MARK: - Event Header Card

    private var eventHeaderCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.event.place)
                        .font(.title2.bold())
                    Text(formatEventDate(viewModel.event.date.dateValue()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isPast {
                    Text("Past")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - RSVP Card

    private var rsvpCard: some View {
        HStack(spacing: 10) {
            RSVPButton(
                title: "Going",
                systemImage: "checkmark",
                isSelected: viewModel.event.participants[currentUserId] == .going,
                isDisabled: isPast,
                selectedColor: .green
            ) {
                let newStatus: ParticipantStatus = viewModel.event.participants[currentUserId] == .going ? .pending : .going
                viewModel.updateParticipantStatus(userId: currentUserId, status: newStatus)
            }
            RSVPButton(
                title: "Not Going",
                systemImage: "xmark",
                isSelected: viewModel.event.participants[currentUserId] == .notGoing,
                isDisabled: isPast,
                selectedColor: .red
            ) {
                let newStatus: ParticipantStatus = viewModel.event.participants[currentUserId] == .notGoing ? .pending : .notGoing
                viewModel.updateParticipantStatus(userId: currentUserId, status: newStatus)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Comment Input Row

    private var commentInputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Add a comment…", text: $viewModel.commentText, axis: .vertical)
                .lineLimit(1...4)
                .padding(10)
                .background(Color(.systemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .focused($isCommentFocused)

            let isCommentEmpty = viewModel.commentText.trimmingCharacters(in: .whitespaces).isEmpty
            Button {
                viewModel.submitComment(userId: currentUserId)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isCommentEmpty ? Color.secondary : Color.primary)
            }
            .disabled(isCommentEmpty || viewModel.isSubmittingComment)
        }
    }
}

// MARK: - RSVPButton

private struct RSVPButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isDisabled: Bool
    let selectedColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? selectedColor : selectedColor.opacity(0.1))
                .foregroundStyle(isSelected ? Color.white : selectedColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - CommentRow

private struct CommentRow: View {
    let comment: Comment
    let author: User?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                if let author {
                    Text(author.fullName)
                        .font(.caption.bold())
                } else {
                    Text("Loading...")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                Text(comment.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    Text(relativeTimeString(from: comment.createdAt.dateValue()))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ProposalRow

private struct ProposalRow: View {
    let proposal: Proposal
    let currentUserId: String
    let isOrganizer: Bool
    let isPast: Bool
    let onVote: (Bool) -> Void
    let onAccept: () -> Void
    let onDeny: () -> Void

    private var hasUpvoted: Bool { proposal.upvotes.contains(currentUserId) }
    private var hasDownvoted: Bool { proposal.downvotes.contains(currentUserId) }
    private var isAccepted: Bool { proposal.status == .accepted }
    private var isRejected: Bool { proposal.status == .rejected }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let place = proposal.proposedPlace {
                Label(place, systemImage: "mappin")
                    .font(.subheadline)
            }
            if let date = proposal.proposedDate {
                Label(formatEventDate(date.dateValue()), systemImage: "calendar")
                    .font(.subheadline)
            }

            HStack(spacing: 12) {
                Button {
                    onVote(true)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: hasUpvoted ? "hand.thumbsup.fill" : "hand.thumbsup")
                        Text("\(proposal.upvotes.count)")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(hasUpvoted ? .green : .secondary)
                }
                .disabled(isPast || isAccepted || isRejected)

                Button {
                    onVote(false)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: hasDownvoted ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        Text("\(proposal.downvotes.count)")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(hasDownvoted ? .red : .secondary)
                }
                .disabled(isPast || isAccepted || isRejected)

                Spacer()

                if isAccepted {
                    Label("Accepted", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else if isRejected {
                    Label("Denied", systemImage: "xmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                } else if isOrganizer && !isPast {
                    Button(action: onAccept) {
                        Text("Accept")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.primary)
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .clipShape(Capsule())
                    }
                    Button(action: onDeny) {
                        Text("Deny")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.12))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(
            isAccepted ? Color.green.opacity(0.08) :
            isRejected ? Color.red.opacity(0.06) :
            Color(.systemFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - EditEventView

private struct EditEventView: View {
    let event: Event
    let onSave: (String, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var place: String
    @State private var date: Date

    init(event: Event, onSave: @escaping (String, Date) -> Void) {
        self.event = event
        self.onSave = onSave
        _place = State(initialValue: event.place)
        _date = State(initialValue: event.date.dateValue())
    }

    private var hasChanges: Bool {
        let trimmed = place.trimmingCharacters(in: .whitespaces)
        return trimmed != event.place || abs(date.timeIntervalSince(event.date.dateValue())) > 1
    }

    private var isValid: Bool {
        !place.trimmingCharacters(in: .whitespaces).isEmpty && hasChanges
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Event Details") {
                    TextField("Place", text: $place)
                    DatePicker(
                        "Date & Time",
                        selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(place.trimmingCharacters(in: .whitespaces), date)
                        dismiss()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
