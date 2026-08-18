import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var store: AppStore
    private var favorite: (String, Double)? { store.preferences.storeWeights.max { $0.value < $1.value } }
    var body: some View {
        NavigationStack { List { Section("Learned preferences") { LabeledContent("Plans selected", value: "\(store.preferences.selectedPlans)"); LabeledContent("Favorite store", value: favorite?.0 ?? "Still learning") }; Section("Store affinity") { if store.preferences.storeWeights.isEmpty { Text("Choose shopping plans and the app will learn which stores you prefer.").foregroundStyle(.secondary) } else { ForEach(store.preferences.storeWeights.sorted(by: { $0.value > $1.value }), id: \.key) { name, weight in HStack { Text(name); Spacer(); Gauge(value: weight, in: 0...max(1, store.preferences.storeWeights.values.max() ?? 1)) { EmptyView() }.frame(width: 130) } } } }; Section("How personalization works") { Label("Preferred stores receive a ranking boost", systemImage: "heart.fill"); Label("Travel time and price remain part of every score", systemImage: "scale.3d"); Label("All preference data stays on this device", systemImage: "lock.shield") } }.navigationTitle("Your preferences") }
    }
}
