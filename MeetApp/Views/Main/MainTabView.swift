import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager

    var body: some View {
        TabView(selection: $tabManager.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(1)

            MenuView()
                .tabItem { Label("Menu", systemImage: "line.3.horizontal") }
                .tag(2)
        }
    }
}
