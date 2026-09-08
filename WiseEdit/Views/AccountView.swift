import SwiftUI
import AuthenticationServices

/// Settings ▸ Account: sign in with Apple, see the plan + remaining cloud
/// minutes, and (later) buy more. Cloud transcription is optional — on-device
/// stays free and private.
struct AccountView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let account = appState.account

        Form {
            Section("Cloud account") {
                if account.isSignedIn {
                    LabeledContent("Plan", value: (account.account?.plan ?? "free").capitalized)
                    LabeledContent("Cloud minutes left",
                                   value: String(format: "%.1f", account.balanceMinutes))
                    HStack {
                        Button("Refresh") { Task { await account.refresh() } }
                        Spacer()
                        Button("Sign Out", role: .destructive) { account.signOut() }
                    }
                } else {
                    Text("Sign in to use cloud transcription — handy on Macs that can't run the model on-device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email]
                    } onCompletion: { result in
                        account.completeAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.whiteOutline)
                    .frame(maxWidth: 260, minHeight: 36)
                }

                if account.isWorking {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Signing in…").foregroundStyle(.secondary) }
                }
                if let err = account.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Buy minutes") {
                Text("Pay-as-you-go cloud minutes are coming soon.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
