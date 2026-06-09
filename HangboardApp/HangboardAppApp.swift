import SwiftUI
import SwiftData

@main
struct HangboardAppApp: App {
    let container: ModelContainer = {
        // Bump this number whenever Item.swift models change — wipes the local
        // store so SwiftData doesn't crash reading columns that didn't exist yet.
        // DataSeeder repopulates historical workout data automatically.
        let schemaVersion = 2

        let schema = Schema([WorkoutSession.self, HangSet.self, FingerInjury.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        if UserDefaults.standard.integer(forKey: "hangboard.schemaVersion") < schemaVersion {
            let url = config.url
            let shm = url.deletingLastPathComponent()
                .appending(path: url.lastPathComponent + "-shm")
            let wal = url.deletingLastPathComponent()
                .appending(path: url.lastPathComponent + "-wal")
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: shm)
            try? FileManager.default.removeItem(at: wal)
            UserDefaults.standard.set(schemaVersion, forKey: "hangboard.schemaVersion")
        }

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
