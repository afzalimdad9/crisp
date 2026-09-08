import Foundation

/// A user's cloud account snapshot.
struct Account: Codable, Equatable {
    var plan: String
    var balanceMinutes: Double
}

/// Auth exchange response from `POST /v1/auth/apple`.
struct AuthResponse: Decodable {
    let token: String
    let account: Account
}

/// One transcribed word from the cloud (`confidence` → `Word.probability`).
struct CloudWordDTO: Decodable {
    let text: String
    let start: Double
    let end: Double
    let confidence: Double
}

/// Response from `POST /v1/transcribe`.
struct TranscribeResponse: Decodable {
    let words: [CloudWordDTO]
    let provider: String
    let minutesCharged: Double
    let balanceMinutes: Double
}

enum APIError: LocalizedError {
    case notSignedIn
    case insufficientCredits(balance: Double, needed: Double)
    case http(Int, String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to use cloud transcription."
        case let .insufficientCredits(balance, needed):
            return String(format: "Not enough cloud minutes (%.1f left, %.1f needed). Buy more to continue.", balance, needed)
        case let .http(code, msg):
            return "Server error \(code): \(msg)"
        case let .transport(msg):
            return "Network error: \(msg)"
        }
    }
}

/// Thin client for the Crisp backend. Stateless — the caller passes the session
/// token for authenticated calls (held by `AccountStore` / Keychain).
struct APIClient {
    var baseURL: URL = AppConfig.apiBaseURL

    func exchangeApple(identityToken: String) async throws -> AuthResponse {
        var req = request("/v1/auth/apple", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["identityToken": identityToken])
        return try await send(req)
    }

    func account(token: String) async throws -> Account {
        var req = request("/v1/account", method: "GET")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func transcribe(audioData: Data, filename: String, mimeType: String,
                    durationSec: Double, token: String) async throws -> TranscribeResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = request("/v1/transcribe", method: "POST")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = multipartBody(boundary: boundary, audio: audioData,
                                     filename: filename, mimeType: mimeType, durationSec: durationSec)
        return try await send(req)
    }

    // MARK: - Plumbing

    private func request(_ path: String, method: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            if code == 402,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let balance = (obj["balanceMinutes"] as? Double) ?? 0
                let needed = (obj["minutesNeeded"] as? Double) ?? 0
                throw APIError.insufficientCredits(balance: balance, needed: needed)
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(code, body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.transport("bad response: \(error.localizedDescription)")
        }
    }

    private func multipartBody(boundary: String, audio: Data, filename: String,
                              mimeType: String, durationSec: Double) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"durationSec\"\r\n\r\n")
        append("\(durationSec)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audio)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}
