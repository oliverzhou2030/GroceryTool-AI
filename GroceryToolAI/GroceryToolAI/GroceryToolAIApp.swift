import SwiftUI

@main
struct GroceryToolAIApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var location = LocationService()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(location)
                #if os(macOS)
                .frame(minWidth: 820, minHeight: 620)
                #endif
        }
    }
}
