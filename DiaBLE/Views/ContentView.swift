import SwiftUI


struct ContentView: View {
    
    @Environment(\.scenePhase) var scenePhase
    @State var backgroundTask: UIBackgroundTaskIdentifier? = nil
    
    @Environment(AppState.self) var app: AppState
    @Environment(Log.self) var log: Log
    @Environment(History.self) var history: History
    @Environment(Settings.self) var settings: Settings

    var body: some View {

        @Bindable var settings = settings

        TabView(selection: $settings.selectedTab) {
            Monitor()
                .tabItem {
                    Label("Monitor", systemImage: "gauge")
                }.tag(Tab.monitor)

            OnlineView()
                .tabItem {
                    Label("Online", systemImage: "globe")
                }.tag(Tab.online)

            ConsoleTab()
                .tabItem {
                    Label("Console", systemImage: "terminal")
                }.tag(Tab.console)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }.tag(Tab.settings)

            DataView()
                .tabItem {
                    Label("Data", systemImage: "tray.full.fill")
                }.tag(Tab.data)

            Plan()
                .tabItem {
                    Label("Plan", systemImage: "map")
                }.tag(Tab.plan)

        }
        .toolbarRole(.navigationStack)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                
            } else if newPhase == .inactive {
                
            } else if newPhase == .background {
                if backgroundTask != nil {
                    UIApplication.shared.endBackgroundTask(backgroundTask!)
                    backgroundTask = UIBackgroundTaskIdentifier.invalid
                }

                backgroundTask = UIApplication.shared.beginBackgroundTask(expirationHandler: { () -> Void in
                    UIApplication.shared.endBackgroundTask(self.backgroundTask!)
                    self.backgroundTask = UIBackgroundTaskIdentifier.invalid
                })
            }
            
        }
    }
}


#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .monitor))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .online))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .data))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .console))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .settings))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}

