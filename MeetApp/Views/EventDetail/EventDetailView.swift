import Combine
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

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
        self.attendees.removeAll { id in
            guard let uid = id.id else { return true }
            return !goingIds.contains(uid)
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

    func vote(on proposal: Proposal, userId: String, isUpvote: Bool) {
        guard let eventId = event.id, let proposalId = proposal.id else { return }
        Task {
            try? await eventService.voteOnProposal(
                eventId: eventId, proposalId: proposalId, userId: userId, isUpvote: isUpvote
            )
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
}

// MARK: - EventDetailView

struct EventDetailView: View {
    @StateObject private var viewModel: EventDetailViewModel
    @EnvironmentObject private var appState: AppState
    @State private var showProposeSheet = false

    init(event: Event) {
        _viewModel = StateObject(wrappedValue: EventDetailViewModel(event: event))
    }

    private var currentUserId: String { appState.authService.currentUser?.uid ?? "" }
    private var isOrganizer: Bool { currentUserId == viewModel.event.organizerId }
    private var isPast: Bool { viewModel.event.date.dateValue() < Date() }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                eventHeaderCard
                rsvpCard
                participantsCard
                commentsCard
                proposalsCard
            }
            .padding(16)
        }
        .background {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.systemGray6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .navigationTitle(viewModel.event.place)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showProposeSheet) {
            ProposeChangeView { proposedPlace, proposedDate in
                viewModel.addProposal(
                    proposerId: currentUserId,
                    proposedPlace: proposedPlace,
                    proposedDate: proposedDate
                )
            }
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
    }

    // MARK: - Event Header Card

    @ViewBuilder
    private var eventHeaderCard: some View {
        let going = viewModel.event.participants.values.filter { $0 == .going }.count
        let notGoing = viewModel.event.participants.values.filter { $0 == .notGoing }.count
        let pending = viewModel.event.participants.values.filter { $0 == .pending }.count

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.event.place)
                        .font(.title2.bold())
                    Text(Self.dateFormatter.string(from: viewModel.event.date.dateValue()))
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

            Divider()

            HStack(spacing: 16) {
                Label("\(going) going", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("\(notGoing) not going", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                if pending > 0 {
                    Label("\(pending) pending", systemImage: "clock")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
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
                isDisabled: isPast
            ) {
                viewModel.updateParticipantStatus(userId: currentUserId, status: .going)
            }
            RSVPButton(
                title: "Not Going",
                systemImage: "xmark",
                isSelected: viewModel.event.participants[currentUserId] == .notGoing,
                isDisabled: isPast
            ) {
                viewModel.updateParticipantStatus(userId: currentUserId, status: .notGoing)
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

    // MARK: - Participants Card

    private var participantsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Going (\(viewModel.attendees.count))")
                .font(.headline)

            if viewModel.attendees.isEmpty {
                Text("No one is going yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.attendees) { user in
                        HStack(spacing: 10) {
                            Image(systemName: "person.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(user.fullName)
                                .font(.subheadline)
                            Spacer()
                        }
                    }
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

    // MARK: - Comments Card

    private var commentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline)

            if viewModel.comments.isEmpty {
                Text("No comments yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.comments) { comment in
                        CommentRow(
                            comment: comment, author: viewModel.commentAuthors[comment.userId])
                        if comment.id != viewModel.comments.last?.id {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Add a comment…", text: $viewModel.commentText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Color(.systemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                let isCommentEmpty = viewModel.commentText.trimmingCharacters(in: .whitespaces)
                    .isEmpty
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
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Proposals Card

    private var proposalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Proposals")
                    .font(.headline)
                Spacer()
                if !isPast {
                    Button {
                        showProposeSheet = true
                    } label: {
                        Label("Propose", systemImage: "plus")
                            .font(.subheadline)
                    }
                }
            }

            if viewModel.proposals.isEmpty {
                Text("No proposals yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.proposals) { proposal in
                        ProposalRow(
                            proposal: proposal,
                            currentUserId: currentUserId,
                            isOrganizer: isOrganizer,
                            isPast: isPast,
                            onVote: { isUpvote in
                                viewModel.vote(
                                    on: proposal, userId: currentUserId, isUpvote: isUpvote)
                            },
                            onAccept: {
                                viewModel.accept(proposal: proposal)
                            }
                        )
                    }
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
}

// MARK: - RSVPButton

private struct RSVPButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Color.primary : Color.primary.opacity(0.08))
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : .primary)
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
                if let author = author {
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
                Text(comment.createdAt.dateValue(), style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
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

    private var hasUpvoted: Bool { proposal.upvotes.contains(currentUserId) }
    private var hasDownvoted: Bool { proposal.downvotes.contains(currentUserId) }
    private var isAccepted: Bool { proposal.status == .accepted }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let place = proposal.proposedPlace {
                Label(place, systemImage: "mappin")
                    .font(.subheadline)
            }
            if let date = proposal.proposedDate {
                Label(Self.dateFormatter.string(from: date.dateValue()), systemImage: "calendar")
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
                .disabled(isPast || isAccepted)

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
                .disabled(isPast || isAccepted)

                Spacer()

                if isAccepted {
                    Label("Accepted", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
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
                }
            }
        }
        .padding(12)
        .background(isAccepted ? Color.green.opacity(0.08) : Color(.systemFill))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
