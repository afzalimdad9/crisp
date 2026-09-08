import Foundation
import Observation
import AuthenticationServices
import AppKit

/// Owns the user's cloud session: Sign in with Apple, the session token (stored
/// in the Keychain), and the cached account (plan + credit balance). Used to gate
/// cloud transcription and shown in Settings ▸ Account.
@Observable
@MainActor
final class AccountStore: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private static let tokenKey = "crisp.sessionToken"
    private let api = APIClient()

    private(set) var token: String?
    private(set) var account: Account?
    private(set) var isWorking = false
    var lastError: String?

    var isSignedIn: Bool { token != nil }
    var balanceMinutes: Double { account?.balanceMinutes ?? 0 }

    override init() {
        super.init()
        token = Keychain.get(Self.tokenKey)
        if token != nil { Task { await refresh() } }
    }

    /// Refreshes the cached account from the server (signs out on 401).
    func refresh() async {
        guard let token else { return }
        do {
            account = try await api.account(token: token)
        } catch APIError.http(401, _) {
            signOut()
        } catch {
            // Keep the cached account on transient errors.
        }
    }

    func signInWithApple() {
        lastError = nil
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func signOut() {
        token = nil
        account = nil
        Keychain.delete(Self.tokenKey)
    }

    /// Completion entry point for SwiftUI's `SignInWithAppleButton`.
    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            handleAuthorization(authorization)
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            lastError = error.localizedDescription
        }
    }

    /// Extracts the identity token from a successful Apple authorization and
    /// exchanges it for our session token. Shared by the SwiftUI button and the
    /// programmatic (`ASAuthorizationController`) flow.
    private func handleAuthorization(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            lastError = "Apple did not return an identity token."
            return
        }
        completeSignIn(identityToken: idToken)
    }

    private func completeSignIn(identityToken: String) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let resp = try await api.exchangeApple(identityToken: identityToken)
                token = resp.token
                account = resp.account
                Keychain.set(resp.token, for: Self.tokenKey)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: ASAuthorizationController

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        handleAuthorization(authorization)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        // User cancelling isn't an error worth surfacing.
        if (error as? ASAuthorizationError)?.code == .canceled { return }
        lastError = error.localizedDescription
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
