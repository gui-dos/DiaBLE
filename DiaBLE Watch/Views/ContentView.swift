import SwiftUI


struct ContentView: View {

    @EnvironmentObject var app: AppState
    @Environment(Log.self) var log: Log
    @Environment(History.self) var history: History
    @Environment(Settings.self) var settings: Settings

    var body: some View {

        @Bindable var settings = settings

        NavigationStack {

            TabView(selection: $settings.selectedTab) {

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }.tag(Tab.settings)

                Monitor()
                    .tabItem {
                        Label("Monitor", systemImage: "gauge")
                    }.tag(Tab.monitor)

                OnlineView()
                    .tabItem {
                        Label("Online", systemImage: "globe")
                    }.tag(Tab.online)

                Console()
                    .tabItem {
                        Label("Console", systemImage: "terminal")
                    }.tag(Tab.console)

                DataView()
                    .tabItem {
                        Label("Data", systemImage: "tray.full.fill")
                    }.tag(Tab.data)

                //  Plan()
                //      .tabItem {
                //          Image(systemName: "map")
                //          Text("Plan")
                //  }.tag(Tab.plan)

            }
            .toolbarBackground(.hidden, for: .navigationBar)

            // FIXME: often hangs
            // .tabViewStyle(.verticalPage)

        }

    }
}


#Preview {
    ContentView()
        .environmentObject(AppState.test(tab: .monitor))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}
