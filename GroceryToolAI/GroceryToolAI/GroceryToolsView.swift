import SwiftUI

struct GroceryToolsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                    NavigationLink {
                        GroceryBudgetView()
                    } label: {
                        toolCard(
                            title: "Grocery Budget",
                            subtitle: "Set a dollar limit and track the current period.",
                            icon: "dollarsign.gauge.chart.leftthird.topthird.rightthird",
                            color: .blue
                        )
                    }
                    NavigationLink {
                        GroceryAIView()
                    } label: {
                        toolCard(
                            title: "Ask Grocery AI",
                            subtitle: "Ask about shopping, substitutions, storage, meals, and receipts.",
                            icon: "sparkles",
                            color: .purple
                        )
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        toolCard(
                            title: "Settings",
                            subtitle: "Manage your account, language, appearance, sync, and location.",
                            icon: "gearshape.fill",
                            color: .gray
                        )
                    }
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Grocery tools")
        }
    }

    private func toolCard(title: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 52, height: 52)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
            Text(title).font(.title3.bold()).foregroundStyle(.primary)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Label("Open", systemImage: "arrow.right.circle.fill")
                .font(.subheadline.bold()).foregroundStyle(Color.appBlue)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.08)))
    }
}

struct GroceryBudgetView: View {
    @EnvironmentObject private var store: AppStore

    private var status: GroceryBudgetStatus? {
        GroceryBudgetService.status(for: store.preferences.groceryBudget, receipts: store.receipts)
    }

    var body: some View {
        Form {
            Section("Dollar limit") {
                Toggle("Use a grocery budget", isOn: $store.preferences.groceryBudget.isEnabled)
                TextField("Expected grocery spending", value: $store.preferences.groceryBudget.amount, format: .currency(code: "USD"))
                    .disabled(!store.preferences.groceryBudget.isEnabled)
                HStack {
                    ForEach([100.0, 500.0, 1_000.0, 3_000.0], id: \.self) { amount in
                        Button(amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))) {
                            store.preferences.groceryBudget.amount = amount
                            store.preferences.groceryBudget.isEnabled = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            Section("Time period") {
                Stepper("Every \(store.preferences.groceryBudget.periodLength) \(periodLabel)", value: $store.preferences.groceryBudget.periodLength, in: 1...12)
                    .disabled(!store.preferences.groceryBudget.isEnabled)
                Picker("Period unit", selection: $store.preferences.groceryBudget.periodUnit) {
                    ForEach(BudgetPeriodUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                }
                .pickerStyle(.segmented)
                .disabled(!store.preferences.groceryBudget.isEnabled)
            }
            if let status {
                Section("Current period") {
                    ProgressView(value: min(max(status.progress, 0), 1))
                        .tint(status.remaining >= 0 ? Color.appBlue : .red)
                    LabeledContent("Limit", value: status.amount.formatted(.currency(code: "USD")))
                    LabeledContent("Spent", value: status.spent.formatted(.currency(code: "USD")))
                    LabeledContent(
                        status.remaining >= 0 ? "Remaining" : "Over budget",
                        value: abs(status.remaining).formatted(.currency(code: "USD"))
                    )
                    Text("\(status.start.formatted(date: .abbreviated, time: .omitted)) – \(status.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Recommendation effect") {
                    Label("Shop recommendations favor plans that fit the money remaining.", systemImage: "cart.badge.clock")
                    Label("Plans over the limit show the amount they exceed it by.", systemImage: "exclamationmark.triangle")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Grocery Budget")
    }

    private var periodLabel: String {
        let unit = store.preferences.groceryBudget.periodUnit.rawValue
        return store.preferences.groceryBudget.periodLength == 1 ? String(unit.dropLast()) : unit
    }
}
