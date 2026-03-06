import Combine
import FirebaseFirestore
import SwiftUI
import FirebaseAuth

@MainActor
class AppState: ObservableObject {
    @Published var currentUser: User?
    @Published var circles: [FriendCircle] = []
    @Published var activeCircle: FriendCircle?

    let authService = AuthService()

    private let userService = UserService()
    private let circleService = CircleService()
    private var userListener: ListenerRegistration?
    private var circlesListener: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()

    init() {
        authService.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] firebaseUser in
                guard let self else { return }
                if let uid = firebaseUser?.uid {
                    self.startListeningToUser(uid: uid)
                    self.startListeningToCircles(userId: uid)
                } else {
                    self.currentUser = nil
                    self.circles = []
                    self.activeCircle = nil
                    self.userListener?.remove()
                    self.circlesListener?.remove()
                }
            }
            .store(in: &cancellables)
    }

    var isAuthenticated: Bool { authService.currentUser != nil }

    func setActiveCircle(_ circle: FriendCircle) {
        activeCircle = circle
    }

    private func startListeningToUser(uid: String) {
        userListener?.remove()
        userListener = userService.listenToUser(uid: uid) { [weak self] user in
            Task { @MainActor [weak self] in
                self?.currentUser = user
            }
        }
    }

    private func startListeningToCircles(userId: String) {
        circlesListener?.remove()
        circlesListener = circleService.listenToCircles(for: userId) { [weak self] circles in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.circles = circles
                if self.activeCircle == nil {
                    self.activeCircle = circles.first
                } else if let active = self.activeCircle, !circles.contains(where: { $0.id == active.id }) {
                    self.activeCircle = circles.first
                }
            }
        }
    }
}
