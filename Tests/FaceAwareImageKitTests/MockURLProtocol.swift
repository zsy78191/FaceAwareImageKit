import Foundation
import Network
import XCTest

nonisolated final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    // Every mutable field is protected by lock; callbacks run outside it.
    nonisolated final class Control: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [MockURLProtocol] = []
        private var starts = 0
        private var stops = 0
        private var startSignals: [(Int, CheckedContinuation<Void, Never>)] = []
        private var stopSignals: [(Int, CheckedContinuation<Void, Never>)] = []

        var requestCount: Int { lock.withLock { starts } }
        var cancellationCount: Int { lock.withLock { stops } }

        func started(_ instance: MockURLProtocol) {
            let signals = lock.withLock {
                starts += 1
                pending.append(instance)
                let ready = startSignals.filter { $0.0 <= starts }
                startSignals.removeAll { $0.0 <= starts }
                return ready
            }
            signals.forEach { $0.1.resume() }
        }

        func stopped() {
            let signals = lock.withLock {
                stops += 1
                let ready = stopSignals.filter { $0.0 <= stops }
                stopSignals.removeAll { $0.0 <= stops }
                return ready
            }
            signals.forEach { $0.1.resume() }
        }

        func waitForRequests(_ count: Int) async {
            await withCheckedContinuation { continuation in
                let ready = lock.withLock {
                    if starts >= count { return true }
                    startSignals.append((count, continuation))
                    return false
                }
                if ready { continuation.resume() }
            }
        }

        func waitForCancellations(_ count: Int) async {
            await withCheckedContinuation { continuation in
                let ready = lock.withLock {
                    if stops >= count { return true }
                    stopSignals.append((count, continuation))
                    return false
                }
                if ready { continuation.resume() }
            }
        }

        func complete(_ index: Int = 0, status: Int = 200, data: Data = Data(), error: Error? = nil,
                      cacheControl: String = "no-store", storagePolicy: URLCache.StoragePolicy = .notAllowed) {
            let instance = lock.withLock { pending[index] }
            if let error {
                instance.client?.urlProtocol(instance, didFailWithError: error)
            } else {
                let response = HTTPURLResponse(url: instance.request.url!, statusCode: status,
                                               httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": cacheControl,
                                                                                     "Content-Type": "image/png"])!
                instance.client?.urlProtocol(instance, didReceive: response, cacheStoragePolicy: storagePolicy)
                instance.client?.urlProtocol(instance, didLoad: data)
                instance.client?.urlProtocolDidFinishLoading(instance)
            }
        }
    }

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var controls: [String: Control] = [:]

    static func register(_ control: Control, for url: URL) {
        registryLock.withLock { controls[url.host!] = control }
    }

    static func unregister(_ url: URL) {
        _ = registryLock.withLock { controls.removeValue(forKey: url.host!) }
    }

    private var control: Control? {
        Self.registryLock.withLock { Self.controls[request.url!.host!] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { control?.started(self) }
    override func stopLoading() { control?.stopped() }
}

// Pauses exactly one completed resource without observing cancellation. Releasing
// it must deliver a successful result to finish, not a synthetic cancelled error.
actor PipelineSuccessBarrier {
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func pause() async {
        guard !entered else { return }
        entered = true
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
            let waiters = entryWaiters
            entryWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

// Holds the ACTUAL URLSession cache-store callback before forwarding it. The
// delayed operation owns its response/task; no thread or actor is blocked.
nonisolated final class HTTPStoreBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private var stores: [(@Sendable () -> Void)?] = []
    private var signals: [(Int, CheckedContinuation<Void, Never>)] = []

    func enqueue(_ store: @escaping @Sendable () -> Void) {
        let ready = lock.withLock {
            stores.append(store)
            let ready = signals.filter { $0.0 <= stores.count }
            signals.removeAll { $0.0 <= stores.count }
            return ready
        }
        ready.forEach { $0.1.resume() }
    }

    func waitForStores(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                if stores.count >= count { return true }
                signals.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func release(_ index: Int) {
        let store = lock.withLock {
            let store = stores[index]
            stores[index] = nil
            return store
        }
        store?()
    }
}

nonisolated final class DelayedHTTPStoreCache: URLCache, @unchecked Sendable {
    private let backing: URLCache
    private let barrier: HTTPStoreBarrier

    init(backing: URLCache, barrier: HTTPStoreBarrier) {
        self.backing = backing
        self.barrier = barrier
        super.init(memoryCapacity: backing.memoryCapacity, diskCapacity: backing.diskCapacity, diskPath: nil)
    }

    override func storeCachedResponse(_ response: CachedURLResponse, for request: URLRequest) {
        barrier.enqueue { [backing] in backing.storeCachedResponse(response, for: request) }
    }

    override func storeCachedResponse(_ response: CachedURLResponse, for task: URLSessionDataTask) {
        barrier.enqueue { [backing] in backing.storeCachedResponse(response, for: task) }
    }

    override func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        backing.cachedResponse(for: request)
    }

    override func getCachedResponse(for task: URLSessionDataTask,
                                    completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void) {
        backing.getCachedResponse(for: task, completionHandler: completionHandler)
    }

    override func removeCachedResponse(for request: URLRequest) { backing.removeCachedResponse(for: request) }
    override func removeCachedResponse(for task: URLSessionDataTask) { backing.removeCachedResponse(for: task) }
    override func removeAllCachedResponses() { backing.removeAllCachedResponses() }
}

// Real loopback HTTP complements URLProtocol race tests: only the native HTTP
// protocol can demonstrate Foundation's server-header freshness decisions.
nonisolated final class PipelineHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "ImagePipelineTests.HTTPServer")
    private let lock = NSLock()
    private let first: Data
    private let next: Data
    private var counts: [String: Int] = [:]
    private var connections: [NWConnection] = []
    private var startupResolved = false

    init(first: Data, next: Data) throws {
        self.first = first
        self.next = next
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                let result: Result<URL, Error>
                switch state {
                case .ready:
                    result = .success(URL(string: "http://127.0.0.1:\(listener.port!.rawValue)")!)
                case .failed(let error): result = .failure(error)
                default: return
                }
                let shouldResume = lock.withLock {
                    if startupResolved { return false }
                    startupResolved = true
                    return true
                }
                if shouldResume { continuation.resume(with: result) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                self.lock.withLock { self.connections.append(connection) }
                connection.start(queue: self.queue)
                self.receive(connection, accumulated: Data())
            }
            listener.start(queue: queue)
        }
    }

    func count(for path: String) -> Int { lock.withLock { counts[path, default: 0] } }

    func stop() {
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
        let active = lock.withLock {
            let active = connections
            connections.removeAll()
            return active
        }
        active.forEach { $0.cancel() }
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, complete, error in
            var accumulated = accumulated
            if let data { accumulated.append(data) }
            guard let request = String(data: accumulated, encoding: .utf8), request.contains("\r\n\r\n") else {
                if complete || error != nil { connection.cancel() }
                else { receive(connection, accumulated: accumulated) }
                return
            }
            let path = String(request.split(separator: " ")[1])
            let count = lock.withLock {
                counts[path, default: 0] += 1
                return counts[path]!
            }
            let body = count == 1 ? first : next
            let policy: String
            switch path {
            case "/no-store": policy = "no-store"
            case "/expired": policy = "max-age=0, must-revalidate"
            case "/no-cache": policy = "no-cache"
            default: policy = "public, max-age=3600"
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            let headers = "HTTP/1.1 200 OK\r\nDate: \(formatter.string(from: Date()))\r\nContent-Type: image/png\r\nCache-Control: \(policy)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(headers.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
