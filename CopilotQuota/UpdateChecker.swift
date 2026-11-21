import Foundation

/// Minimal semantic version parser & comparator for release tags like `v1.4.0` or `1.4.0-beta.1`.
struct SemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String?

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        guard !stripped.isEmpty else { return nil }

        let parts = stripped.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let coreComponents = parts[0].split(separator: ".")
        guard !coreComponents.isEmpty, coreComponents.count <= 3 else { return nil }

        var nums: [Int] = []
        for comp in coreComponents {
            guard let n = Int(comp), n >= 0 else { return nil }
            nums.append(n)
        }
        while nums.count < 3 { nums.append(0) }

        self.major = nums[0]
        self.minor = nums[1]
        self.patch = nums[2]
        if parts.count == 2, !parts[1].isEmpty {
            self.prerelease = String(parts[1])
        } else {
            self.prerelease = nil
        }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (.some, nil): return true   // 1.0.0-beta < 1.0.0
        case (nil, .some): return false  // 1.0.0 > 1.0.0-beta
        case (.some(let l), .some(let r)): return l.localizedStandardCompare(r) == .orderedAscending
        }
    }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let draft: Bool?
    let prerelease: Bool?
    let assets: [Asset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

struct UpdateInfo: Equatable {
    let version: String
    let downloadURL: URL
    let releaseURL: URL
}

enum UpdateCheckResult: Equatable {
    case available(UpdateInfo)
    case upToDate
    case failed(String)
}

/// Zero-dependency update checker backed by GitHub Releases API.
struct UpdateChecker {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/addozhang/CopilotQuota/releases/latest")!

    /// Pure comparison logic — easy to unit test without networking.
    static func evaluate(release: GitHubRelease, currentVersion: String) -> UpdateInfo? {
        guard release.draft != true, release.prerelease != true else { return nil }
        guard let latest = SemanticVersion(release.tagName),
              let current = SemanticVersion(currentVersion),
              latest > current else {
            return nil
        }
        let dmgURL = release.assets?
            .first(where: { $0.name.lowercased().hasSuffix(".dmg") })?
            .browserDownloadURL
        let cleanVersion = release.tagName.hasPrefix("v") || release.tagName.hasPrefix("V")
            ? String(release.tagName.dropFirst())
            : release.tagName
        return UpdateInfo(
            version: cleanVersion,
            downloadURL: dmgURL ?? release.htmlURL,
            releaseURL: release.htmlURL
        )
    }

    func check(currentVersion: String = AppInfo.version) async -> UpdateCheckResult {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CopilotQuota/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                return .failed(L("Update check failed (HTTP %d).", status))
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            if let info = Self.evaluate(release: release, currentVersion: currentVersion) {
                return .available(info)
            }
            return .upToDate
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
