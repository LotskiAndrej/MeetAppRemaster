import FirebaseFirestore

struct Comment: Codable, Identifiable {
    @DocumentID var id: String?
    var userId: String
    var text: String
    var createdAt: Timestamp
}
