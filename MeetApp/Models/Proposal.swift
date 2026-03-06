import FirebaseFirestore

enum ProposalStatus: String, Codable {
    case pending
    case accepted
    case rejected
}

struct Proposal: Codable, Identifiable {
    @DocumentID var id: String?
    var proposerId: String
    var proposedPlace: String?
    var proposedDate: Timestamp?
    var upvotes: [String]
    var downvotes: [String]
    var status: ProposalStatus
    var createdAt: Timestamp
}
