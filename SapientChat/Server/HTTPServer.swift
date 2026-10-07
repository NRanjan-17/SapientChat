import Foundation
import Network

/// A small HTTP/1.1 server on Network.framework: one request per
/// connection, streamed responses sent with chunked encoding. All socket
/// state lives on one serial queue.
nonisolated final class HTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    enum State: Equatable, Sendable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    struct Configuration: Equatable, Sendable {
        var port: UInt16
        /// Accept connections from other devices; otherwise loopback only
        /// (apps on this device, e.g. side by side on iPad).
        var allowsNetwork: Bool
        /// Bonjour name to advertise as `_http._tcp`; nil advertises nothing.
        var bonjourName: String?
    }

    private let queue = DispatchQueue(label: "SapientChat.HTTPServer")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]

    /// Starts listening. `onState` reports on the server's queue.
    func start(
        _ configuration: Configuration,
        handler: @escaping Handler,
        onState: @escaping @Sendable (State) -> Void
    ) {
        queue.async { [self] in
            stopOnQueue()
            guard let port = NWEndpoint.Port(rawValue: configuration.port), configuration.port > 0 else {
                onState(.failed("Port \(configuration.port) is not valid."))
                return
            }
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            if !configuration.allowsNetwork {
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
            }
            let listener: NWListener
            do {
                listener = configuration.allowsNetwork
                    ? try NWListener(using: parameters, on: port)
                    : try NWListener(using: parameters)
            } catch {
                onState(.failed("Couldn't open port \(configuration.port): \(error.localizedDescription)"))
                return
            }
            if let name = configuration.bonjourName, configuration.allowsNetwork {
                listener.service = NWListener.Service(name: name, type: "_http._tcp")
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                switch state {
                case .setup, .waiting: onState(.starting)
                case .ready: onState(.running)
                case .failed(let error):
                    onState(.failed(error.localizedDescription))
                    listener?.cancel()
                    self?.listener = nil
                case .cancelled: onState(.stopped)
                @unknown default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection, handler: handler)
            }
            self.listener = listener
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.async { [self] in stopOnQueue() }
    }

    private func stopOnQueue() {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.close()
        }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection, handler: @escaping Handler) {
        let http = HTTPConnection(connection: connection, queue: queue, handler: handler)
        let key = ObjectIdentifier(http)
        connections[key] = http
        http.onClose = { [weak self] in self?.connections[key] = nil }
        http.start()
    }
}

/// One client connection: reads a request, runs the handler, writes the
/// response, closes. If the client goes away mid-response, the handler's
/// stream is cancelled, which stops generation.
nonisolated private final class HTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let handler: HTTPServer.Handler
    private var buffer = Data()
    private var responding: Task<Void, Never>?
    private var isClosed = false
    /// Runs on the server's queue once the connection ends.
    var onClose: (() -> Void)?

    init(connection: NWConnection, queue: DispatchQueue, handler: @escaping HTTPServer.Handler) {
        self.connection = connection
        self.queue = queue
        self.handler = handler
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if responding != nil {
                // The request is in; anything now is the client hanging up.
                if error != nil || isComplete { responding?.cancel() } else { receive() }
                return
            }
            if let data { buffer.append(data) }
            switch HTTPRequestParser.parse(buffer) {
            case .complete(let request):
                respond(to: request)
                receive()
            case .invalid(let status, let reason):
                respond(with: .json(ServeErrorBody.invalidRequest(reason), status: status))
            case .incomplete:
                if error != nil || isComplete { close() } else { receive() }
            }
        }
    }

    private func respond(to request: HTTPRequest) {
        let handler = handler
        responding = Task { [self] in
            await write(await handler(request))
        }
    }

    private func respond(with response: HTTPResponse) {
        responding = Task { [self] in await write(response) }
    }

    private func write(_ response: HTTPResponse) async {
        do {
            try await send(response.head())
            switch response.body {
            case .data(let data):
                if !data.isEmpty { try await send(data) }
            case .stream(let chunks):
                for try await chunk in chunks where !chunk.isEmpty {
                    try Task.checkCancellation()
                    try await send(HTTPResponse.chunk(chunk))
                }
                try await send(HTTPResponse.chunk(Data()))
            }
        } catch {
            // Client gone or generation failed mid-stream: just close.
        }
        queue.async { [self] in close() }
    }

    private func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    /// Call on the server's queue.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        responding?.cancel()
        connection.cancel()
        onClose?()
        onClose = nil
    }
}
