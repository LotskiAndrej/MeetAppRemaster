import FirebaseFirestore

struct User: Codable, Identifiable {
    @DocumentID var id: String?
    var firstName: String
    var lastName: String
    var circleIds: [String]

    var fullName: String { "\(firstName) \(lastName)" }
}
