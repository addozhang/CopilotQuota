import Foundation

enum QuotaError: LocalizedError {
    case unauthorized
    case notFound
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return L("GitHub token is invalid or expired (401). Please sign in again.")
        case .notFound:
            return L("This account is not enrolled in GitHub Copilot, or the API is unavailable (404).")
        case .http(let code):
            return L("GitHub API request failed (HTTP %d).", code)
        }
    }
}

/// Client for `GET https://api.github.com/copilot_internal/user`.
///
/// Header set mirrors what the VS Code Copilot extension sends
/// (verified by CodexBar / OpenTokenUsage).
struct CopilotQuotaClient {
    static let url = URL(string: "https://api.github.com/copilot_internal/user")!

    func fetch(token: String) async throws -> CopilotUserResponse {
        var request = URLRequest(url: Self.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            return try JSONDecoder().decode(CopilotUserResponse.self, from: data)
        case 401:
            throw QuotaError.unauthorized
        case 404:
            throw QuotaError.notFound
        default:
            throw QuotaError.http(status)
        }
    }
}
