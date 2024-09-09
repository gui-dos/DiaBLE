import SwiftUI


struct HamburgerMenu: View {

    let credits = [
        "@bubbledevteam": "https://github.com/bubbledevteam",
        "@captainbeeheart": "https://github.com/captainbeeheart",
        "@creepymonster": "https://github.com/creepymonster",
        "@cryptax": "https://github.com/cryptax",
        "CryptoSwift": "https://github.com/krzyzanowskim/CryptoSwift",
        "@dabear": "https://github.com/dabear",
        "@DecentWoodpecker67": "https://github.com/DecentWoodpecker67",
        "Glucosy": "https://github.com/TopScrech/Glucosy",
        "@ivalkou": "https://github.com/ivalkou",
        "Jaap Korthals Altes": "https://github.com/j-kaltes",
        "@keencave": "https://github.com/keencave",
        "LibreMonitor": "https://github.com/UPetersen/LibreMonitor/tree/Swift4",
        "LibreWrist": "https://github.com/poml88/LibreWrist",
        "Loop": "https://github.com/LoopKit/Loop",
        "Marek Macner": "https://github.com/MarekM60",
        "@monder": "https://github.com/monder",
        "Nightguard": "https://github.com/nightscout/nightguard",
        "Nightscout LibreLink Up Uploader": "https://github.com/timoschlueter/nightscout-librelink-up",
        "@travisgoodspeed": "https://github.com/travisgoodspeed",
        "WoofWoof": "https://github.com/gshaviv/ninety-two",
        "xDrip": "https://github.com/Faifly/xDrip",
        "xDrip+": "https://github.com/NightscoutFoundation/xDrip",
        "xDrip4iO5": "https://github.com/JohanDegraeve/xdripswift"
    ]

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(spacing: 4) {

                    HStack(spacing: 10) {
                        NavigationLink(destination: Monitor()) {
                            VStack {
                                Image(systemName: "gauge").resizable().frame(width: 40, height: 40).offset(y: 4)
                                Text("Monitor")
                                    .bold()
                                    .foregroundStyle(.blue)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        NavigationLink(destination: Details()) {
                            VStack {
                                Image("Bluetooth").renderingMode(.template).resizable().frame(width: 40, height: 40).offset(y: 4)
                                Text("Details")
                                    .bold()
                                    .foregroundStyle(.blue)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, -4)

                    HStack(spacing: 10) {
                        NavigationLink(destination: Console()) {
                            VStack {
                                Image(systemName: "terminal").resizable().frame(width: 40, height: 40).offset(y: 4)
                                Text("Console")
                                    .bold()
                                    .foregroundStyle(.blue)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        NavigationLink(destination: SettingsView()) {
                            VStack {
                                Image(systemName: "gear").resizable().frame(width: 40, height: 40).offset(y: 4)
                                Text("Settings")
                                    .bold()
                                    .foregroundStyle(.blue)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    HStack(spacing: 10) {
                        NavigationLink(destination: DataView()) {
                            VStack {
                                Image(systemName: "tray.full.fill").resizable().frame(width: 40, height: 40).offset(y: 4)
                                Text("Data")
                                    .bold()
                                    .foregroundStyle(.blue)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        NavigationLink(destination: OnlineView()) {
                            VStack {
                                Image(systemName: "globe").resizable().frame(width: 40, height: 40).offset(y: 4)
                                Text("Online")
                                    .bold()
                                    .foregroundStyle(.blue)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // TODO: Help and About sheets
                    // HStack(spacing: 10) {
                    //     VStack {
                    //         Image(systemName: "questionmark.circle").resizable().frame(width: 40, height: 40).offset(y: 4)
                    //         Text("Help")
                    //             .bold()
                    //             .foregroundStyle(.blue)
                    //     }
                    //     .frame(maxWidth: .infinity)
                    //     VStack {
                    //         Image(systemName: "info.circle").resizable().frame(width: 40, height: 40).offset(y: 4)
                    //         Text("About")
                    //             .bold()
                    //             .foregroundStyle(.blue)
                    //     }
                    //     .frame(maxWidth: .infinity)
                    // }
                }
                .foregroundStyle(.red)

                Spacer(minLength: 30)

                VStack(spacing: 20) {
                    VStack {

                        Text("DiaBLE  \(Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String)  (\(Bundle.main.infoDictionary!["CFBundleVersion"] as! String))")

                        // TODO: get AppIcon 1024x1024
                        // Image("AppIcon").resizable().frame(width: 100, height: 100)
                        // FIXME: doesn't work in watchOS 10
                        if let uiImage = UIImage(named: "AppIcon") {
                            Image(uiImage: uiImage).resizable().frame(width: 100, height: 100)
                        }
                        Link("https://github.com/gui-dos/DiaBLE",
                             destination: URL(string: "https://github.com/gui-dos/DiaBLE")!)
                        .foregroundStyle(.blue)
                    }

                    VStack {
                        Image(systemName: "envelope.fill")
                        Link(Data(base64Encoded: "Z3VpZG8uc29yYW56aW9AZ21haWwuY29t")!.string,
                             destination: URL(string: "mailto:\(Data(base64Encoded: "Z3VpZG8uc29yYW56aW9AZ21haWwuY29t")!.string)")!)
                        .foregroundStyle(.blue)
                    }

                    VStack {
                        Image(systemName: "giftcard")
                        Link(Data(base64Encoded: "aHR0cHM6Ly9wYXlwYWwubWUvZ3Vpc29y")!.string, destination: URL(string: Data(base64Encoded: "aHR0cHM6Ly9wYXlwYWwubWUvZ3Vpc29y")!.string)!)
                            .foregroundStyle(.blue)
                    }

                    VStack {
                        Text("Credits:")
                        ScrollView {
                            ForEach(credits.sorted(by: <), id: \.key) { name, url in
                                VStack {
                                    Text(name)
                                    Link((url), destination: URL(string: url)!)
                                        .foregroundStyle(.blue)
                                }
                                .font(.footnote)
                                .padding(.vertical, 6)
                            }
                        }
                    }

                }
                .foregroundStyle(.white)

            }
            .buttonStyle(.borderless)
            .navigationTitle { Text("DiaBLE").foregroundStyle(.tint) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarForegroundStyle(.blue, for: .automatic)
            .tint(.blue)

        }
        .padding(.top, -4)
        .edgesIgnoringSafeArea([.bottom])

    }
}



#Preview {
    HamburgerMenu()
}
