import Foundation

private final class ProxyAuthenticationDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  let username: String
  let password: String

  init(username: String, password: String) {
    self.username = username
    self.password = password
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    if challenge.protectionSpace.isProxy(), !username.isEmpty {
      completionHandler(
        .useCredential,
        URLCredential(user: username, password: password, persistence: .forSession)
      )
    } else {
      completionHandler(.performDefaultHandling, nil)
    }
  }
}

struct HTTPResult {
  var data: Data
  var response: HTTPURLResponse

  var statusCode: Int { response.statusCode }

  func jsonObject() throws -> Any {
    try JSONSerialization.jsonObject(with: data)
  }

  func jsonDictionary() throws -> [String: Any] {
    guard let dict = try jsonObject() as? [String: Any] else {
      throw UsageError.invalidResponse("Expected a JSON object")
    }
    return dict
  }
}

struct HTTPClient: Sendable {
  static let shared = HTTPClient()

  func send(
    _ url: URL,
    method: String = "GET",
    headers: [String: String] = [:],
    body: Data? = nil,
    timeout: TimeInterval = 8,
    proxyOverride: AppProxyConfiguration? = nil,
    proxyPasswordOverride: String? = nil
  ) async throws -> HTTPResult {
    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = method
    request.httpBody = body
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }

    let config = URLSessionConfiguration.ephemeral
    config.waitsForConnectivity = false
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.timeoutIntervalForRequest = timeout
    config.timeoutIntervalForResource = timeout + 2
    let proxy: AppProxyConfiguration
    let password: String
    if let proxyOverride {
      proxy = proxyOverride
      password = proxyPasswordOverride ?? ""
    } else if let profile = await SharedStore.shared.activeProxyProfile(for: url) {
      proxy = profile.configuration
      password = (try? KeychainStore.shared.proxyPassword(profileID: profile.id)) ?? ""
    } else {
      proxy = .disabled
      password = ""
    }
    if let dictionary = proxy.connectionProxyDictionary(password: password) {
      config.connectionProxyDictionary = dictionary
    }
    let delegate = ProxyAuthenticationDelegate(username: proxy.username, password: password)
    let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw proxyError(error, proxy: proxy)
    }
    guard let http = response as? HTTPURLResponse else {
      throw UsageError.invalidResponse("No HTTP response")
    }
    return HTTPResult(data: data, response: http)
  }

  private func proxyError(_ error: Error, proxy: AppProxyConfiguration) -> Error {
    guard proxy.isEnabled else { return error }
    let failure = error as NSError
    guard failure.domain == "kCFErrorDomainCFNetwork" else { return error }
    switch abs(failure.code) {
    case 306, 310:
      return UsageError.refreshFailed("代理连接失败（CFNetwork \(abs(failure.code))）。请在设置中测试服务，并确认 HTTP 代理支持 HTTPS CONNECT。")
    case 307:
      return UsageError.refreshFailed("代理认证失败，请检查用户名和密码。")
    default:
      return error
    }
  }
}

func formURLEncoded(_ values: [String: String]) -> Data {
  let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
  let body = values.compactMap { key, value -> String? in
    guard let k = key.addingPercentEncoding(withAllowedCharacters: allowed),
      let v = value.addingPercentEncoding(withAllowedCharacters: allowed)
    else { return nil }
    return "\(k)=\(v)"
  }.joined(separator: "&")
  return Data(body.utf8)
}

func number(_ value: Any?) -> Double? {
  switch value {
  case let n as NSNumber: n.doubleValue
  case let s as String: Double(s)
  default: nil
  }
}

func boolValue(_ value: Any?) -> Bool? {
  switch value {
  case let b as Bool: b
  case let n as NSNumber: n.boolValue
  case let s as String:
    switch s.lowercased() {
    case "true", "1": true
    case "false", "0": false
    default: nil
    }
  default: nil
  }
}

func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
func array(_ value: Any?) -> [[String: Any]]? { value as? [[String: Any]] }

func parseDate(_ value: Any?) -> Date? {
  if let n = number(value), n > 0 {
    let seconds = n > 10_000_000_000 ? n / 1000 : n
    return Date(timeIntervalSince1970: seconds)
  }
  guard let raw = value as? String, !raw.isEmpty else { return nil }
  let iso = ISO8601DateFormatter()
  iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = iso.date(from: raw) { return date }
  iso.formatOptions = [.withInternetDateTime]
  if let date = iso.date(from: raw) { return date }

  let dateOnly = DateFormatter()
  dateOnly.locale = Locale(identifier: "en_US_POSIX")
  dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
  dateOnly.dateFormat = "yyyy-MM-dd"
  return dateOnly.date(from: raw)
}

func durationLabel(seconds: Double?) -> String {
  guard let seconds, seconds > 0 else { return "额度" }
  if abs(seconds - 18_000) <= 60 { return "5h" }
  if abs(seconds - 604_800) <= 600 { return "周" }
  if (2_500_000...2_700_000).contains(seconds) { return "30d" }
  if seconds.truncatingRemainder(dividingBy: 86_400) == 0 {
    return "\(Int(seconds / 86_400))d"
  }
  if seconds.truncatingRemainder(dividingBy: 3_600) == 0 {
    return "\(Int(seconds / 3_600))h"
  }
  return "额度"
}

func clampPercent(_ value: Double) -> Double { min(100, max(0, value)) }

func decodeJWTPayload(_ token: String?) -> [String: Any]? {
  guard let token, !token.isEmpty else { return nil }
  let pieces = token.split(separator: ".")
  guard pieces.count > 1 else { return nil }
  var base64 = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(
    of: "_", with: "/")
  let padding = (4 - base64.count % 4) % 4
  base64 += String(repeating: "=", count: padding)
  guard let data = Data(base64Encoded: base64),
    let object = try? JSONSerialization.jsonObject(with: data),
    let dict = object as? [String: Any]
  else { return nil }
  return dict
}

func findNestedString(_ object: Any, key: String) -> String? {
  if let dict = object as? [String: Any] {
    if let value = dict[key] as? String { return value }
    for value in dict.values {
      if let found = findNestedString(value, key: key) { return found }
    }
  } else if let list = object as? [Any] {
    for value in list {
      if let found = findNestedString(value, key: key) { return found }
    }
  }
  return nil
}
