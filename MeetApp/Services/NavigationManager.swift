import SwiftUI
import Combine

enum HomeDestination: Hashable {
    case eventDetail(Event)
}

@MainActor
class NavigationManager: ObservableObject {
    @Published var homePath = NavigationPath()

    func popToRoot() {
        homePath = NavigationPath()
    }
}
