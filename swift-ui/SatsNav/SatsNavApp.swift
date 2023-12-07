import Starscream
import SwiftData
import SwiftUI

let BTC = LedgerEntry.Asset(name: "BTC", type: .crypto)

class SharedData: ObservableObject {
    @Published var startDate = Date.now
}

@main
struct SatsNavApp: App {
    @StateObject var shared = SharedData()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(shared: shared)
        }
        .modelContainer(sharedModelContainer)
    }
}
