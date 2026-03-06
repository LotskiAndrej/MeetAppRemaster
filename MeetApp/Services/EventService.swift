import Foundation
import FirebaseFirestore

class EventService {
    private let db = Firestore.firestore()

    // MARK: - Events

    /// Real-time listener for all events in a circle, ordered by date.
    func listenToEvents(circleId: String, completion: @escaping ([Event]) -> Void) -> ListenerRegistration {
        db.collection("events")
            .whereField("circleId", isEqualTo: circleId)
            .order(by: "date")
            .addSnapshotListener { snapshot, _ in
                let events = snapshot?.documents.compactMap { try? $0.data(as: Event.self) } ?? []
                completion(events)
            }
    }

    func createEvent(_ event: Event) throws {
        let ref = db.collection("events").document()
        var newEvent = event
        newEvent.id = ref.documentID
        try ref.setData(from: newEvent)
    }

    func updateParticipantStatus(eventId: String, userId: String, status: ParticipantStatus) async throws {
        try await db.collection("events").document(eventId).updateData([
            "participants.\(userId)": status.rawValue
        ])
    }

    /// Real-time listener for a single event document.
    func listenToEvent(eventId: String, completion: @escaping (Event?) -> Void) -> ListenerRegistration {
        db.collection("events").document(eventId)
            .addSnapshotListener { snapshot, _ in
                let event = try? snapshot?.data(as: Event.self)
                completion(event)
            }
    }

    // MARK: - Comments

    /// Real-time listener for comments on an event, ordered by creation time.
    func listenToComments(eventId: String, completion: @escaping ([Comment]) -> Void) -> ListenerRegistration {
        db.collection("events").document(eventId).collection("comments")
            .order(by: "createdAt")
            .addSnapshotListener { snapshot, _ in
                let comments = snapshot?.documents.compactMap { try? $0.data(as: Comment.self) } ?? []
                completion(comments)
            }
    }

    func addComment(_ comment: Comment, to eventId: String) throws {
        let ref = db.collection("events").document(eventId).collection("comments").document()
        var newComment = comment
        newComment.id = ref.documentID
        try ref.setData(from: newComment)
    }

    // MARK: - Proposals

    /// Real-time listener for proposals on an event, ordered by creation time.
    func listenToProposals(eventId: String, completion: @escaping ([Proposal]) -> Void) -> ListenerRegistration {
        db.collection("events").document(eventId).collection("proposals")
            .order(by: "createdAt")
            .addSnapshotListener { snapshot, _ in
                let proposals = snapshot?.documents.compactMap { try? $0.data(as: Proposal.self) } ?? []
                completion(proposals)
            }
    }

    func addProposal(_ proposal: Proposal, to eventId: String) throws {
        let ref = db.collection("events").document(eventId).collection("proposals").document()
        var newProposal = proposal
        newProposal.id = ref.documentID
        try ref.setData(from: newProposal)
    }

    func voteOnProposal(eventId: String, proposalId: String, userId: String, isUpvote: Bool) async throws {
        let ref = db.collection("events").document(eventId).collection("proposals").document(proposalId)
        if isUpvote {
            try await ref.updateData([
                "upvotes": FieldValue.arrayUnion([userId]),
                "downvotes": FieldValue.arrayRemove([userId])
            ])
        } else {
            try await ref.updateData([
                "downvotes": FieldValue.arrayUnion([userId]),
                "upvotes": FieldValue.arrayRemove([userId])
            ])
        }
    }

    /// Accepts a proposal: marks it accepted and updates the parent event's place/date.
    func acceptProposal(eventId: String, proposal: Proposal) async throws {
        guard let proposalId = proposal.id else { return }
        try await db.collection("events").document(eventId)
            .collection("proposals").document(proposalId)
            .updateData(["status": ProposalStatus.accepted.rawValue])

        var eventUpdates: [String: Any] = [:]
        if let place = proposal.proposedPlace { eventUpdates["place"] = place }
        if let date = proposal.proposedDate { eventUpdates["date"] = date }
        if !eventUpdates.isEmpty {
            try await db.collection("events").document(eventId).updateData(eventUpdates)
        }
    }
}
