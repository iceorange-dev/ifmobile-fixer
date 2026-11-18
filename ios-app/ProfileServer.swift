import Foundation
import Network
import UIKit

/// Serves the bundled profile only to Safari on this device. iOS presents the
/// download/installation prompts; this does not install profiles silently.
@MainActor final class ProfileServer {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var background: UIBackgroundTaskIdentifier = .invalid
    private var expiry: DispatchWorkItem?
    private var delivered = false
    func start(completion: @escaping (Result<URL, Error>) -> Void) {
        stop()
        guard let file = Bundle.main.url(forResource: "ifmobile-Roaming-Voice", withExtension: "mobileconfig"), let data = try? Data(contentsOf: file) else {
            completion(.failure(NSError(domain: "Profile", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到正式描述檔"]))); return
        }
        let path = "/\(UUID().uuidString)/ifmobile-Roaming-Voice.mobileconfig"
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            let server = try NWListener(using: params)
            listener = server; delivered = false
            background = UIApplication.shared.beginBackgroundTask(withName: "ProfileDownload") { [weak self] in
                // The expiration handler must end the task before it returns, or iOS terminates the app.
                MainActor.assumeIsolated { self?.stop() }
            }
            var returned = false
            server.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    switch state {
                    case .ready:
                        guard !returned, let port = server.port else { return }; returned = true
                        completion(.success(URL(string: "http://127.0.0.1:\(port.rawValue)\(path)")!))
                    case .failed(let e):
                        if !returned { returned = true; completion(.failure(e)) }; self?.stop()
                    default: break
                    }
                }
            }
            server.newConnectionHandler = { [weak self] conn in
                MainActor.assumeIsolated {
                    guard let self, self.connections.count < 4 else { conn.cancel(); return }
                    self.connections.append(conn); conn.start(queue: .main)
                    self.receive(conn, buffer: Data(), path: path, payload: data)
                }
            }
            let expiry = DispatchWorkItem { [weak self] in self?.stop() }; self.expiry = expiry
            DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: expiry)
            server.start(queue: .main)
        } catch { stop(); completion(.failure(error)) }
    }
    private func receive(_ connection: NWConnection, buffer: Data, path: String, payload: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
                guard let self else { connection.cancel(); return }
                var buffer = buffer; if let data { buffer.append(data) }
                guard error == nil, buffer.count <= 16384 else { self.drop(connection); return }
                let request = String(decoding: buffer, as: UTF8.self)
                guard request.contains("\r\n\r\n") else {
                    if complete { self.drop(connection) } else { self.receive(connection, buffer: buffer, path: path, payload: payload) }; return
                }
                let allowed = request.hasPrefix("GET \(path) HTTP/")
                let body = allowed ? payload : Data("Not found".utf8)
                let header = allowed ? "HTTP/1.1 200 OK\r\nContent-Type: application/x-apple-aspen-config\r\nContent-Disposition: attachment; filename=ifmobile-Roaming-Voice.mobileconfig\r\n" : "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n"
                var response = Data((header + "Content-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n").utf8); response.append(body)
                connection.send(content: response, completion: .contentProcessed { _ in
                    MainActor.assumeIsolated { self.drop(connection) }
                })
                self.delivered = self.delivered || allowed
            }
        }
    }
    /// Closes one connection and frees its slot, so the limit counts open connections, not every one ever made.
    private func drop(_ connection: NWConnection) {
        connection.cancel(); connections.removeAll { $0 === connection }
    }
    func stop() {
        expiry?.cancel(); expiry = nil; listener?.cancel(); listener = nil
        connections.forEach { $0.cancel() }; connections = []
        if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
    }
}
