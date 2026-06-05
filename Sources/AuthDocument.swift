import Foundation

enum AuthDocument {
    static func validate(_ data: Data) throws -> AuthIdentity {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["tokens"] != nil || root["OPENAI_API_KEY"] != nil || root["agent_identity"] != nil
        else {
            throw CXSwitchError.invalidAuth
        }

        let mode = root["auth_mode"] as? String ?? inferredMode(from: root)
        let tokens = root["tokens"] as? [String: Any]
        let accountID = tokens?["account_id"] as? String
        let idToken = tokens?["id_token"] as? String
        let claims = idToken.flatMap(jwtPayload)
        let email = claims?["email"] as? String

        return AuthIdentity(email: email, accountID: accountID, mode: mode)
    }

    static func accessToken(from data: Data) throws -> String {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = root["tokens"] as? [String: Any],
            let accessToken = tokens["access_token"] as? String,
            !accessToken.isEmpty
        else {
            throw CXSwitchError.invalidAuth
        }
        return accessToken
    }

    private static func inferredMode(from root: [String: Any]) -> String {
        if root["OPENAI_API_KEY"] != nil { return "API Key" }
        if root["agent_identity"] != nil { return "Access Token" }
        return "ChatGPT"
    }

    private static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)

        guard
            let data = Data(base64Encoded: encoded),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return payload
    }
}
