import SwiftUI
import Combine

@MainActor
class TabManager: ObservableObject {
    @Published var selectedTab: Int = 0
}
