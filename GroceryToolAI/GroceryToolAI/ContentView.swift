import SwiftUI
import CoreLocation
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationService
    private var colorScheme: ColorScheme? {
        switch store.preferences.theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var body: some View {
        Group {
            if store.currentUsername == nil {
                AuthView()
            } else {
                authenticatedContent
            }
        }
        .tint(Color.appBlue)
        .preferredColorScheme(colorScheme)
    }

    @ViewBuilder private var authenticatedContent: some View {
        #if os(iOS)
        if location.isAuthorized { mainTabs } else { LocationPermissionView() }
        #else
        mainTabs
        #endif
    }

    private var mainTabs: some View {
        TabView {
            ReceiptsView().tabItem { Label("Receipts", systemImage: "receipt") }
            InsightsView().tabItem { Label("Insights", systemImage: "chart.pie.fill") }
            ShoppingSearchView().tabItem { Label("Shop", systemImage: "magnifyingglass") }
            PreferencesView().tabItem { Label("Preferences", systemImage: "heart.text.square") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .background(Color.appBackground)
    }
}

#if os(iOS)
private struct LocationPermissionView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationService
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.circle.fill").font(.system(size: 64)).foregroundStyle(Color.appBlue)
            Text("Current location required").font(.title.bold())
            Text("Your location lets GroceryTool AI find nearby shops and calculate realistic travel options. It is used only while the app is open.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 430)
            if location.authorizationStatus == .denied {
                Button("Open iPhone Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }.buttonStyle(.borderedProminent)
            } else {
                Button("Allow current location") { location.requestAccess() }.buttonStyle(.borderedProminent)
            }
            Button("Sign out") { store.signOut() }.foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .onAppear { if location.authorizationStatus == .notDetermined { location.requestAccess() } }
    }
}
#endif

#Preview { ContentView().environmentObject(AppStore()).environmentObject(LocationService()) }
