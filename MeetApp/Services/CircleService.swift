import Foundation
import FirebaseFirestore

enum CircleError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound: "No circle found with that invite code."
        }
    }
}

class CircleService {
    private let db = Firestore.firestore()

    /// Creates a new circle, adds the admin as the first member, and updates the admin's user doc.
    func createCircle(name: String, adminId: String) async throws -> FriendCircle {
        let ref = db.collection("circles").document()
        let circle = FriendCircle(
            id: ref.documentID,
            name: name,
            adminId: adminId,
            inviteCode: generateInviteCode(),
            memberIds: [adminId]
        )
        try ref.setData(from: circle)
        try await db.collection("users").document(adminId).updateData([
            "circleIds": FieldValue.arrayUnion([ref.documentID])
        ])
        return circle
    }

    /// Finds a circle by invite code and adds the user as a member.
    func joinCircle(inviteCode: String, userId: String) async throws {
        let snapshot = try await db.collection("circles")
            .whereField("inviteCode", isEqualTo: inviteCode)
            .getDocuments()
        guard let doc = snapshot.documents.first else { throw CircleError.notFound }
        let circleId = doc.documentID
        try await db.collection("circles").document(circleId).updateData([
            "memberIds": FieldValue.arrayUnion([userId])
        ])
        try await db.collection("users").document(userId).updateData([
            "circleIds": FieldValue.arrayUnion([circleId])
        ])
    }

    /// Real-time listener for all circles a user belongs to.
    func listenToCircles(for userId: String, completion: @escaping ([FriendCircle]) -> Void) -> ListenerRegistration {
        db.collection("circles")
            .whereField("memberIds", arrayContains: userId)
            .addSnapshotListener { snapshot, _ in
                let circles = snapshot?.documents.compactMap { try? $0.data(as: FriendCircle.self) } ?? []
                completion(circles)
            }
    }

    /// Removes a member from the circle and removes the circle from the user's circleIds.
    func kickMember(circleId: String, userId: String) async throws {
        try await db.collection("circles").document(circleId).updateData([
            "memberIds": FieldValue.arrayRemove([userId])
        ])
        try await db.collection("users").document(userId).updateData([
            "circleIds": FieldValue.arrayRemove([circleId])
        ])
    }

    private func generateInviteCode() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}
