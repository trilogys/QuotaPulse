import Foundation
import Network

final class LoopbackOAuthServer: @unchecked Sendable {
  enum ServerError: LocalizedError {
    case failed(String)
    case timeout
    case cancelled
    case invalidRequest

    var errorDescription: String? {
      switch self {
      case .failed(let message): "OAuth callback listener failed: \(message)"
      case .timeout: "OAuth login timed out"
      case .cancelled: "OAuth login was cancelled"
      case .invalidRequest: "Invalid OAuth callback request"
      }
    }
  }

  private let port: NWEndpoint.Port
  var rawPort: UInt16 { port.rawValue }
  private let queue = DispatchQueue(label: "QuotaPulse.LoopbackOAuthServer")
  private let lock = NSLock()
  private var listener: NWListener?
  private var readyContinuation: CheckedContinuation<Void, Error>?
  private var callbackContinuation: CheckedContinuation<URL, Error>?
  private var pendingCallback: URL?
  private var completed = false

  init(port: UInt16 = 1455) {
    self.port = NWEndpoint.Port(rawValue: port)!
  }

  func start() async throws {
    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    let listener = try NWListener(using: parameters, on: port)
    self.listener = listener

    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      readyContinuation = continuation
      lock.unlock()

      listener.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          self.finishReady(.success(()))
        case .failed(let error):
          self.finishReady(.failure(ServerError.failed(error.localizedDescription)))
          self.finishCallback(.failure(ServerError.failed(error.localizedDescription)))
        case .cancelled:
          break
        default:
          break
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        self?.handle(connection)
      }
      listener.start(queue: queue)
    }
  }

  func waitForCallback(timeout: TimeInterval = 300) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      if let pending = pendingCallback {
        pendingCallback = nil
        lock.unlock()
        continuation.resume(returning: pending)
        return
      }
      if completed {
        lock.unlock()
        continuation.resume(throwing: ServerError.cancelled)
        return
      }
      callbackContinuation = continuation
      lock.unlock()

      queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
        self?.finishCallback(.failure(ServerError.timeout))
        self?.listener?.cancel()
      }
    }
  }

  func cancel() {
    finishCallback(.failure(ServerError.cancelled))
    listener?.cancel()
  }

  private func finishReady(_ result: Result<Void, Error>) {
    lock.lock()
    let continuation = readyContinuation
    readyContinuation = nil
    lock.unlock()
    continuation?.resume(with: result)
  }

  private func finishCallback(_ result: Result<URL, Error>) {
    lock.lock()
    guard !completed else {
      lock.unlock()
      return
    }
    completed = true
    let continuation = callbackContinuation
    callbackContinuation = nil
    if continuation == nil, case .success(let url) = result {
      pendingCallback = url
      completed = false
    }
    lock.unlock()
    continuation?.resume(with: result)
  }

  private func handle(_ connection: NWConnection) {
    connection.start(queue: queue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
      [weak self] data, _, _, error in
      guard let self else { return }
      if let error {
        self.finishCallback(.failure(ServerError.failed(error.localizedDescription)))
        connection.cancel()
        return
      }
      guard let data, let request = String(data: data, encoding: .utf8),
        let firstLine = request.components(separatedBy: "\r\n").first
      else {
        self.reply(connection, status: "400 Bad Request", body: "Invalid request")
        return
      }
      let pieces = firstLine.split(separator: " ")
      guard pieces.count >= 2 else {
        self.reply(connection, status: "400 Bad Request", body: "Invalid request")
        return
      }
      let path = String(pieces[1])
      guard let url = URL(string: "http://localhost:\(self.port.rawValue)\(path)"),
        url.path == "/auth/callback"
      else {
        self.reply(connection, status: "404 Not Found", body: "Not Found")
        return
      }

      let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{font-family:-apple-system;background:#111;color:#fff;text-align:center;padding:48px}h2{margin-top:30vh}p{color:#aaa}</style></head>
        <body><h2>Codex 登录成功</h2><p>可以返回 QuotaPulse。</p></body></html>
        """
      self.reply(connection, status: "200 OK", body: html, contentType: "text/html; charset=utf-8")
      self.finishCallback(.success(url))
      self.listener?.cancel()
    }
  }

  private func reply(
    _ connection: NWConnection, status: String, body: String,
    contentType: String = "text/plain; charset=utf-8"
  ) {
    let bodyData = Data(body.utf8)
    let header =
      "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
    var payload = Data(header.utf8)
    payload.append(bodyData)
    connection.send(
      content: payload,
      completion: .contentProcessed { _ in
        connection.cancel()
      })
  }
}
