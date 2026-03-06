import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tabManager: TabManager
    @State private var showCreateEvent = false

    var body: some View {
        TabView(selection: $tabManager.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            // Center "+" tab — intercepted to show the create event sheet
            Color.clear
                .tabItem { Image(systemName: "plus.circle.fill") }
                .tag(1)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(2)

            MenuView()
                .tabItem { Label("Menu", systemImage: "line.3.horizontal") }
                .tag(3)
        }
        .onChange(of: tabManager.selectedTab) { _, tab in
            if tab == 1 {
                showCreateEvent = true
                tabManager.selectedTab = 0
            }
        }
        .sheet(isPresented: $showCreateEvent) {
            CreateEventView()
                .environmentObject(appState)
        }
    }
}
