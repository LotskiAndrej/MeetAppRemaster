import FirebaseFirestore

enum ParticipantStatus: String, Codable {
    case going
    case notGoing = "not_going"
    case pending
}

struct Event: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    var circleId: String
    var organizerId: String
    var place: String
    var date: Timestamp
    var createdAt: Timestamp
    var participants: [String: ParticipantStatus]

    static func == (lhs: Event, rhs: Event) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
