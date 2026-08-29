import CryptoKit
import Foundation

struct PKCEPair: Sendable {
  let verifier: String
  let challenge: String

  static func generate() -> PKCEPair {
    let verifier = randomBase64URL(byteCount: 32)
    let digest = SHA256.hash(data: Data(verifier.utf8))
    let challenge = Data(digest).base64URLEncodedString()
    return PKCEPair(verifier: verifier, challenge: challenge)
  }
}

func randomBase64URL(byteCount: Int = 32) -> String {
  var bytes = [UInt8](repeating: 0, count: byteCount)
  _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
  return Data(bytes).base64URLEncodedString()
}

extension Data {
  fileprivate func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

func queryEncodedURL(base: String, parameters: [(String, String)]) -> URL {
  var components = URLComponents(string: base)!
  components.queryItems = parameters.map { URLQueryItem(name: $0.0, value: $0.1) }
  return components.url!
}
