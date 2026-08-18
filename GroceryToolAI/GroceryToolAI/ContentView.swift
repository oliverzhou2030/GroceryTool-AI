import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        TabView {
            ReceiptsView().tabItem { Label("Receipts", systemImage: "receipt") }
            InsightsView().tabItem { Label("Insights", systemImage: "chart.pie.fill") }
            ShoppingSearchView().tabItem { Label("Shop", systemImage: "magnifyingglass") }
            PreferencesView().tabItem { Label("Preferences", systemImage: "heart.text.square") }
        }
        .tint(.green)
    }
}

#Preview { ContentView().environmentObject(AppStore()) }
