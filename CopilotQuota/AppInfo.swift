import Foundation

enum AppInfo {
    static let repoURL = URL(string: "https://github.com/addozhang/CopilotQuota")!
    static let issuesURL = URL(string: "https://github.com/addozhang/CopilotQuota/issues")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
