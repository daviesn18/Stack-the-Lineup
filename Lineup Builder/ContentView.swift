import SwiftUI

struct ContentView: View {
    @StateObject var store = LineupStore()
    @State private var showingWelcome = !UserDefaults.standard.bool(forKey: "hasCompletedTutorial")
    @State private var showingArchive = false

    var body: some View {
        TabView {
            PlayersView()
                .tabItem {
                    Label("Players", systemImage: "person.3.fill")
                }

            LineupView(showingArchive: $showingArchive)
                .tabItem {
                    Label("Lineup", systemImage: "list.number")
                }

            DefensiveGridView(showingArchive: $showingArchive)
                .tabItem {
                    Label("Positions", systemImage: "baseball.diamond.bases")
                }

            GameLogsView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
        .environmentObject(store)
        .tint(.blue)
        .sheet(isPresented: $showingWelcome) {
            WelcomeView()
        }
        .sheet(isPresented: $showingArchive) {
            ArchiveGameSheet()
                .environmentObject(store)
        }
    }
}
