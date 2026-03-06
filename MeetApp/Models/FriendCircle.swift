import FirebaseFirestore

struct FriendCircle: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var name: String
    var adminId: String
    var inviteCode: String
    var memberIds: [String]
}
