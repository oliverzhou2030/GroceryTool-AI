import SwiftUI
import CoreLocation

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationService

    private var account: LocalAccount? { store.accounts.first { $0.username == store.currentUsername } }

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Name", value: account?.displayName ?? "")
                    LabeledContent("Username", value: account?.username ?? "")
                    Button("Sign out", role: .destructive) { store.signOut() }
                }
                Section("Appearance") {
                    Picker("Color mode", selection: $store.preferences.theme) {
                        ForEach(AppTheme.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Label("The app uses white and light blue in Light mode.", systemImage: "paintpalette.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Language") {
                    Picker("App language", selection: $store.preferences.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    Label("Language changes apply immediately.", systemImage: "globe")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Learned preferences") {
                    LabeledContent("Plans selected", value: "\(store.preferences.selectedPlans)")
                    LabeledContent("Favorite store", value: store.preferences.storeWeights.max(by: { $0.value < $1.value })?.key ?? "Still learning")
                    LabeledContent("Category corrections", value: "\(store.preferences.categoryOverrides.count)")
                    Label("Shopping choices and category corrections automatically improve future results.", systemImage: "heart.text.square")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Current location") {
                    LabeledContent("Permission", value: location.statusText)
                    if let coordinate = location.location?.coordinate {
                        LabeledContent("Latitude", value: coordinate.latitude.formatted(.number.precision(.fractionLength(4))))
                        LabeledContent("Longitude", value: coordinate.longitude.formatted(.number.precision(.fractionLength(4))))
                    }
                    if let error = location.errorMessage { Text(error).foregroundStyle(.red).font(.footnote) }
                    Button(location.isAuthorized ? "Refresh current location" : "Allow location access") { location.refreshLocation() }
                }
                Section("Privacy") {
                    Label("Accounts, reviews, receipts, and preferences stay on this device.", systemImage: "lock.shield.fill")
                    Label("Only approximate location is requested while the app is in use.", systemImage: "location.circle.fill")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Settings")
        }
    }
}
