import Foundation

enum AppInfo {
    static let repoURL = URL(string: "https://github.com/addozhang/QuotaRing")!
    static let issuesURL = URL(string: "https://github.com/addozhang/QuotaRing/issues")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
