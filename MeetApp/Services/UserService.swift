import Foundation
import FirebaseFirestore

class UserService {
    private let db = Firestore.firestore()

    func createUser(_ user: User) throws {
        guard let id = user.id else { return }
        try db.collection("users").document(id).setData(from: user)
    }

    func fetchUser(uid: String) async throws -> User {
        let doc = try await db.collection("users").document(uid).getDocument()
        return try doc.data(as: User.self)
    }

    func updateUser(_ user: User) throws {
        guard let id = user.id else { return }
        try db.collection("users").document(id).setData(from: user, merge: true)
    }

    func listenToUser(uid: String, completion: @escaping (User?) -> Void) -> ListenerRegistration {
        db.collection("users").document(uid).addSnapshotListener { snapshot, _ in
            completion(try? snapshot?.data(as: User.self))
        }
    }
}
