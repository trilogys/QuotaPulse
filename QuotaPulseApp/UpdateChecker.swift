import Foundation

struct AvailableAppUpdate: Sendable {
  let version: String
  let releaseURL: URL
}

enum UpdateChecker {
  static func check() async throws -> AvailableAppUpdate? {
    let result = try await HTTPClient.shared.send(
      URL(string: "https://api.github.com/repos/trilogys/QuotaPulse/releases/latest")!,
      headers: [
        "Accept": "application/vnd.github+json",
        "User-Agent": "QuotaPulse-iOS",
        "X-GitHub-Api-Version": "2022-11-28",
      ],
      timeout: 15
    )
    if result.statusCode == 404 {
      throw UsageError.invalidResponse("暂未发布可在线检查的 Release")
    }
    guard (200..<300).contains(result.statusCode) else {
      throw UsageError.http(result.statusCode, String(data: result.data, encoding: .utf8) ?? "")
    }
    let root = try result.jsonDictionary()
    guard let rawVersion = root["tag_name"] as? String,
          let releaseURLString = root["html_url"] as? String,
          let releaseURL = URL(string: releaseURLString) else {
      throw UsageError.invalidResponse("Release 缺少版本或下载页")
    }
    let version = rawVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    guard compare(version, AppConfig.version) == .orderedDescending else { return nil }
    return AvailableAppUpdate(version: version, releaseURL: releaseURL)
  }

  private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let left = lhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    let right = rhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    for index in 0..<max(left.count, right.count) {
      let a = index < left.count ? left[index] : 0
      let b = index < right.count ? right[index] : 0
      if a < b { return .orderedAscending }
      if a > b { return .orderedDescending }
    }
    return .orderedSame
  }
}
