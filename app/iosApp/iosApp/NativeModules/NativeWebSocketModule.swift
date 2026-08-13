import Foundation
import UIKit

private final class NativeWebSocketConnection {
  let id: String
  let task: URLSessionWebSocketTask
  var terminal = false
  var closing = false
  var requestedCloseCode = 1000
  var requestedCloseReason = ""

  init(id: String, task: URLSessionWebSocketTask) {
    self.id = id
    self.task = task
  }
}

/// Page-owned production WebSocket transport independent of Lynx DevTool.
@objcMembers
final class NativeWebSocketController: NSObject, URLSessionWebSocketDelegate {
  static let eventName = "nativeWebSocket"

  private weak var lynxView: LynxView?
  private let lock = NSLock()
  private var connectionsByID: [String: NativeWebSocketConnection] = [:]
  private var connectionsByTaskID: [Int: NativeWebSocketConnection] = [:]
  private var destroyed = false
  private var sessionWasUsed = false

  private lazy var delegateQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "com.lynxapp.websocket"
    queue.maxConcurrentOperationCount = 1
    return queue
  }()

  private lazy var session: URLSession = URLSession(
    configuration: .default,
    delegate: self,
    delegateQueue: delegateQueue
  )

  func attach(lynxView: LynxView) {
    self.lynxView = lynxView
  }

  func connect(
    id: String,
    url: String,
    protocols: [String],
    headers: [String: String]
  ) -> String {
    guard id.range(
      of: "^[A-Za-z0-9._-]{1,128}$",
      options: .regularExpression
    ) != nil else {
      return "Invalid WebSocket connection ID"
    }
    guard isAllowedURL(url), let targetURL = URL(string: url) else {
      return "WebSocket URL must use wss:// (ws:// is Debug-only)"
    }

    lock.lock()
    let canConnect = !destroyed && connectionsByID[id] == nil
    lock.unlock()
    guard canConnect else {
      return destroyed
        ? "WebSocket host has been destroyed"
        : "WebSocket connection ID already exists"
    }

    var request = URLRequest(url: targetURL)
    for (name, value) in headers {
      request.addValue(value, forHTTPHeaderField: name)
    }
    if !protocols.isEmpty {
      request.setValue(
        protocols.joined(separator: ", "),
        forHTTPHeaderField: "Sec-WebSocket-Protocol"
      )
    }
    sessionWasUsed = true
    let task = session.webSocketTask(with: request)
    let connection = NativeWebSocketConnection(id: id, task: task)

    lock.lock()
    guard !destroyed, connectionsByID[id] == nil else {
      lock.unlock()
      task.cancel()
      return destroyed
        ? "WebSocket host has been destroyed"
        : "WebSocket connection ID already exists"
    }
    connectionsByID[id] = connection
    connectionsByTaskID[task.taskIdentifier] = connection
    lock.unlock()

    task.resume()
    receiveNext(connection)
    return ""
  }

  func sendText(
    id: String,
    data: String,
    completion: @escaping (String) -> Void
  ) {
    send(id: id, message: .string(data), completion: completion)
  }

  func sendBase64(
    id: String,
    data: String,
    completion: @escaping (String) -> Void
  ) {
    guard let decoded = Data(base64Encoded: data) else {
      completion("Invalid Base64 WebSocket payload")
      return
    }
    send(id: id, message: .data(decoded), completion: completion)
  }

  func close(id: String, code: Int, reason: String) -> String {
    guard let connection = connection(forID: id) else {
      return "Unknown WebSocket connection ID"
    }
    guard let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) else {
      return "Invalid WebSocket close code"
    }
    connection.closing = true
    connection.requestedCloseCode = code
    connection.requestedCloseReason = reason
    connection.task.cancel(
      with: closeCode,
      reason: reason.data(using: .utf8)
    )
    return ""
  }

  func destroy() {
    lock.lock()
    guard !destroyed else {
      lock.unlock()
      return
    }
    destroyed = true
    let connections = Array(connectionsByID.values)
    connectionsByID.removeAll()
    connectionsByTaskID.removeAll()
    lynxView = nil
    lock.unlock()

    for connection in connections {
      connection.task.cancel(with: .goingAway, reason: nil)
    }
    if sessionWasUsed {
      session.invalidateAndCancel()
    }
  }

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    guard let connection = connection(forTaskID: webSocketTask.taskIdentifier) else {
      return
    }
    emit(id: connection.id, payload: [
      "type": "open",
      "protocol": `protocol` ?? "",
    ])
  }

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    guard let connection = takeConnection(forTaskID: webSocketTask.taskIdentifier) else {
      return
    }
    emitClose(
      id: connection.id,
      code: closeCode.rawValue,
      reason: reason.flatMap { String(data: $0, encoding: .utf8) } ?? "",
      wasClean: true
    )
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error,
          let connection = connection(forTaskID: task.taskIdentifier) else {
      return
    }
    if connection.closing,
       (error as NSError).domain == NSURLErrorDomain,
       (error as NSError).code == NSURLErrorCancelled {
      guard takeConnection(forTaskID: task.taskIdentifier) != nil else { return }
      emitClose(
        id: connection.id,
        code: connection.requestedCloseCode,
        reason: connection.requestedCloseReason,
        wasClean: true
      )
      return
    }
    guard takeConnection(forTaskID: task.taskIdentifier) != nil else { return }
    emitFailure(id: connection.id, message: error.localizedDescription)
  }

  private func send(
    id: String,
    message: URLSessionWebSocketTask.Message,
    completion: @escaping (String) -> Void
  ) {
    guard let connection = connection(forID: id) else {
      completion("Unknown WebSocket connection ID")
      return
    }
    connection.task.send(message) { error in
      completion(error?.localizedDescription ?? "")
    }
  }

  private func receiveNext(_ connection: NativeWebSocketConnection) {
    connection.task.receive { [weak self, weak connection] result in
      guard let self, let connection,
            self.connection(forID: connection.id) === connection else {
        return
      }
      switch result {
      case let .success(message):
        switch message {
        case let .string(value):
          self.emit(id: connection.id, payload: [
            "type": "message",
            "dataType": "text",
            "data": value,
          ])
        case let .data(value):
          self.emit(id: connection.id, payload: [
            "type": "message",
            "dataType": "base64",
            "data": value.base64EncodedString(),
          ])
        @unknown default:
          self.emitFailure(
            id: connection.id,
            message: "Unsupported WebSocket message type"
          )
          return
        }
        self.receiveNext(connection)
      case let .failure(error):
        if connection.closing { return }
        guard self.takeConnection(forID: connection.id) != nil else { return }
        self.emitFailure(id: connection.id, message: error.localizedDescription)
      }
    }
  }

  private func connection(forID id: String) -> NativeWebSocketConnection? {
    lock.lock()
    defer { lock.unlock() }
    return destroyed ? nil : connectionsByID[id]
  }

  private func connection(forTaskID id: Int) -> NativeWebSocketConnection? {
    lock.lock()
    defer { lock.unlock() }
    return destroyed ? nil : connectionsByTaskID[id]
  }

  private func takeConnection(forID id: String) -> NativeWebSocketConnection? {
    lock.lock()
    defer { lock.unlock() }
    guard !destroyed, let connection = connectionsByID.removeValue(forKey: id) else {
      return nil
    }
    connectionsByTaskID.removeValue(forKey: connection.task.taskIdentifier)
    connection.terminal = true
    return connection
  }

  private func takeConnection(forTaskID id: Int) -> NativeWebSocketConnection? {
    lock.lock()
    defer { lock.unlock() }
    guard !destroyed, let connection = connectionsByTaskID.removeValue(forKey: id) else {
      return nil
    }
    connectionsByID.removeValue(forKey: connection.id)
    connection.terminal = true
    return connection
  }

  private func emitFailure(id: String, message: String) {
    emit(id: id, payload: [
      "type": "error",
      "message": message,
    ])
    emitClose(id: id, code: 1006, reason: message, wasClean: false)
  }

  private func emitClose(
    id: String,
    code: Int,
    reason: String,
    wasClean: Bool
  ) {
    emit(id: id, payload: [
      "type": "close",
      "code": code,
      "reason": reason,
      "wasClean": wasClean,
    ])
  }

  private func emit(id: String, payload: [String: Any]) {
    var event = payload
    event["id"] = id
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.lock.lock()
      let canEmit = !self.destroyed
      self.lock.unlock()
      if canEmit {
        self.lynxView?.sendGlobalEvent(Self.eventName, withParams: [event])
      }
    }
  }

  private func isAllowedURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value),
          components.host != nil,
          let scheme = components.scheme?.lowercased() else {
      return false
    }
    if scheme == "wss" { return true }
    #if DEBUG
    return scheme == "ws"
    #else
    return false
    #endif
  }
}

/// Lynx NativeModule facade for the app-owned iOS WebSocket controller.
@objcMembers
final class NativeWebSocketModule: NSObject, LynxModule {
  static let name = "NativeWebSocketModule"
  static let methodLookup = [
    "connect": "connect:callback:",
    "sendText": "sendText:data:callback:",
    "sendBase64": "sendBase64:data:callback:",
    "close": "close:code:reason:callback:",
  ]

  private weak var controller: NativeWebSocketController?

  @objc(initWithParam:)
  init(param: Any) {
    controller = param as? NativeWebSocketController
    super.init()
  }

  override init() {
    super.init()
  }

  func connect(_ options: NSDictionary, callback: LynxCallbackBlock) {
    guard let controller else {
      callback("Native WebSocket has no UIViewController host")
      return
    }
    let id = options["id"] as? String ?? ""
    let url = options["url"] as? String ?? ""
    let protocols = options["protocols"] as? [String] ?? []
    let headers = options["headers"] as? [String: String] ?? [:]
    callback(controller.connect(
      id: id,
      url: url,
      protocols: protocols,
      headers: headers
    ))
  }

  func sendText(
    _ id: String,
    data: String,
    callback: @escaping LynxCallbackBlock
  ) {
    guard let controller else {
      callback("Native WebSocket has no UIViewController host")
      return
    }
    controller.sendText(id: id, data: data, completion: callback)
  }

  func sendBase64(
    _ id: String,
    data: String,
    callback: @escaping LynxCallbackBlock
  ) {
    guard let controller else {
      callback("Native WebSocket has no UIViewController host")
      return
    }
    controller.sendBase64(id: id, data: data, completion: callback)
  }

  func close(
    _ id: String,
    code: Int,
    reason: String,
    callback: LynxCallbackBlock
  ) {
    callback(
      controller?.close(id: id, code: code, reason: reason)
        ?? "Native WebSocket has no UIViewController host"
    )
  }
}
