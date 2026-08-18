import SwiftUI

@main
struct GroceryToolAIApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene { WindowGroup { ContentView().environmentObject(store).frame(minWidth: 820, minHeight: 620) } }
}
