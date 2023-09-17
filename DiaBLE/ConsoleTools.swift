import Foundation
import SwiftUI
import RealmSwift


// TODO: rename to Copilot when smarter :-)


struct ShellView: View {

    @EnvironmentObject var app: AppState
    @EnvironmentObject var log: Log
    @EnvironmentObject var settings: Settings

    @State private var showingStack = false

    @State private var showingFileImporter = false
    @State private var tridentContainer = ""

    @State private var showingRealmKeyPrompt = false
    @AppStorage("tridentRealmKey") var tridentRealmKey = ""  // 128-char hex

    var body: some View {

        VStack(spacing: 0) {

            if showingStack {
                HStack {

                    Spacer()

                    TextField("Trident Container", text: $tridentContainer)
                        .truncationMode(.head)

                    Button {
                        showingFileImporter = true
                    } label: {
                        Image(systemName: "folder.circle")
                            .font(.system(size: 32))
                    }
                    .fileImporter(
                        isPresented: $showingFileImporter,
                        allowedContentTypes: [.folder]  // .directory doesn't work
                    ) { result in
                        switch result {
                        case .success(let directory):
                            if !directory.startAccessingSecurityScopedResource() { return }
                            tridentContainer = directory.path
                            let fileManager = FileManager.default
                            let containerDirs = try! fileManager.contentsOfDirectory(atPath: tridentContainer)
                            app.main.log("ls \(tridentContainer)\n\(containerDirs)")

                            for dir in containerDirs {

                                if dir == "Library" {
                                    let libraryDirs = try! fileManager.contentsOfDirectory(atPath: "\(tridentContainer)/Library")
                                    app.main.log("ls Library\n\(libraryDirs)")
                                    for dir in libraryDirs {
                                        if dir == "Preferences" {
                                            let preferencesContents = try! fileManager.contentsOfDirectory(atPath: "\(tridentContainer)/Library/Preferences")
                                            app.main.log("ls Preferences\n\(preferencesContents)")
                                            for plist in preferencesContents {
                                                if plist.hasPrefix("com.abbott.libre3") {
                                                    if let plistData = fileManager.contents(atPath:"\(tridentContainer)/Library/Preferences/\(plist)") {
                                                        if let libre3Plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
                                                            app.main.log("cat \(plist)\n\(libre3Plist)")
                                                            let realmEncryptionKey = libre3Plist["RealmEncryptionKey"] as! [UInt8]
                                                            let realmEncryptionKeyInt8 = realmEncryptionKey.map { Int8(bitPattern: $0) }
                                                            app.main.log("realmEncryptionKey:\n\(realmEncryptionKey)\nas Int8 array:\n\(realmEncryptionKeyInt8)")

                                                            // https://frdmtoplay.com/freeing-glucose-data-from-the-freestyle-libre-3/
                                                            //
                                                            // adb root
                                                            // sudo waydroid shell
                                                            // # /data/local/tmp/frida-server &
                                                            //
                                                            // $ frida -U "Libre 3"
                                                            // Frida-> Java.perform(function(){}); // Seems necessary to use Java.use
                                                            // Frida-> var crypto_lib_def = Java.use("com.adc.trident.app.frameworks.mobileservices.libre3.security.Libre3SKBCryptoLib");
                                                            // Frida-> var crypto_lib = crypto_lib_def.$new()
                                                            // Frida-> unwrapped = crypto_lib.unWrapDBEncryptionKey([<realmEncryptionKeyInt8>])
                                                            //
                                                            //
                                                            // let unwrappedInt8: [Int8] = [<unwrapped>]
                                                            // let unwrappedUInt8: [UInt8] = unwrappedInt8.map { UInt8(bitPattern: $0) }
                                                            // log(Data(unwrappedUInt8).reduce("", { $0 + String(format: "%02x", $1)}))

                                                            // TODO: parse rest of libre3Plist
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                if dir == "Documents" {
                                    let documentsFiles = try! fileManager.contentsOfDirectory(atPath: "\(tridentContainer)/Documents")
                                    app.main.log("ls Documents\n\(documentsFiles)")
                                    for file in documentsFiles {
                                        do {
                                            if file.hasSuffix(".realm") && !file.contains("backup") {
                                                var realm: Realm
                                                var config = Realm.Configuration.defaultConfiguration
                                                config.fileURL = URL(filePath: "\(tridentContainer)/Documents/\(file)")
                                                config.schemaVersion = 8  // as for RealmStudio 14
                                                do {
                                                    if !file.contains("decrypted") {
                                                        config.encryptionKey = tridentRealmKey.bytes
                                                    } else {
                                                        config.encryptionKey = nil
                                                    }
                                                    realm = try Realm(configuration: config)
                                                    if !file.contains("decrypted") {
                                                        app.main.debugLog("Realm: opened encrypted \(tridentContainer)/Documents/\(file) by using the key \(tridentRealmKey)")
                                                    } else {
                                                        app.main.debugLog("Realm: opened already decrypted \(tridentContainer)/Documents/\(file)")
                                                    }
                                                    let sensors = realm.objects(SensorEntity.self)
                                                    app.main.log("Realm: sensors: \(sensors)")
                                                    let appConfig = realm.objects(AppConfigEntity.self)
                                                    // overcome limit of max 100 objects in a result description
                                                    app.main.log(appConfig.reduce("Realm: app config:", { $0 + "\n" + $1.description }))
                                                    let libre3WrappedKAuth = realm.object(ofType: AppConfigEntity.self, forPrimaryKey: "Libre3WrappedKAuth")!["_configValue"]!
                                                    app.main.log("Realm: libre3WrappedKAuth: \(libre3WrappedKAuth)")
                                                    // TODO
                                                } catch {
                                                    app.main.log("Realm: error: \(error.localizedDescription)")
                                                    if file == "trident.realm" {
                                                        showingRealmKeyPrompt = true
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                            }

                            directory.stopAccessingSecurityScopedResource()
                        case .failure(let error):
                            app.main.log("\(error.localizedDescription)")
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
        }
        .sheet(isPresented: $showingRealmKeyPrompt) {
            VStack(spacing: 20) {
                Text("The Realm might be encrypted").fontWeight(.bold)
                Text("Either this is not a Realm file or it's encrypted.")
                TextField("128-character hex-encoded encyption key", text: $tridentRealmKey, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingRealmKeyPrompt = false
                    }
                    Button("Try again") {
                        showingRealmKeyPrompt = false
                        showingFileImporter = true
                    }
                }
                .buttonStyle(.bordered)
                .padding()
            }
        }
        .toolbar {
            Button {
                withAnimation { showingStack.toggle() }
            } label: {
                VStack(spacing: 0) {
                    Image(systemName: showingStack ? "fossil.shell.fill" : "fossil.shell")
                    Text("Shell").font(.footnote)
                }
            }
        }
    }
}


#Preview {
    ShellView()
        .preferredColorScheme(.dark)
        .environmentObject(AppState.test(tab: .console))
        .environmentObject(Log())
        .environmentObject(Settings())
}
