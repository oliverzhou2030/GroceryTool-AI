import SwiftUI
import CoreLocation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AuthView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationService
    @State private var creatingAccount = false
    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "cart.fill.badge.plus")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.appBlue)
                        .padding(22)
                        .background(.white.opacity(0.9), in: Circle())
                        .shadow(color: .blue.opacity(0.14), radius: 16, y: 8)
                    VStack(spacing: 8) {
                        Text("GroceryTool AI").font(.largeTitle.bold())
                        Text("Cleaner receipts. Smarter grocery trips.").foregroundStyle(.secondary)
                    }
                    Picker("Account action", selection: $creatingAccount) {
                        Text("Sign in").tag(false)
                        Text("Create account").tag(true)
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 14) {
                        if creatingAccount {
                            TextField("Display name", text: $displayName)
                                .textContentType(.name)
                                .textFieldStyle(.roundedBorder)
                        }
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        SecureField("Password", text: $password)
                            .textContentType(creatingAccount ? .newPassword : .password)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(submit)
                    }

                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }

                    Button(creatingAccount ? "Create my account" : "Sign in", action: submit)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(username.isEmpty || password.isEmpty)

                    VStack(spacing: 8) {
                        Label("Location helps compare nearby shops and travel times.", systemImage: "location.fill")
                        Button(location.authorizationStatus == .notDetermined ? "Allow current location" : "Refresh location") { location.requestAccess() }
                            .buttonStyle(.bordered)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Text("Demo administrator: admin / admin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Color.appBackground.ignoresSafeArea())
        }
    }

    private func submit() {
        if creatingAccount {
            errorMessage = store.createAccount(username: username, displayName: displayName, password: password)
        } else if !store.signIn(username: username, password: password) {
            errorMessage = "Incorrect username or password."
        } else {
            errorMessage = nil
        }
        if store.currentUsername != nil { location.refreshLocation() }
    }
}

extension Color {
    static let appBlue = Color(red: 0.23, green: 0.62, blue: 0.92)
    static let appBackground = Color(light: Color(red: 0.94, green: 0.98, blue: 1), dark: Color(red: 0.05, green: 0.10, blue: 0.15))

    init(light: Color, dark: Color) {
        #if os(iOS)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #else
        self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light) })
        #endif
    }
}
