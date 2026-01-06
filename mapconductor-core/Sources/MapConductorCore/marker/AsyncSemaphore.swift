import Foundation

public final class AsyncSemaphore {
    private let lock = NSLock()
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(_ permits: Int) {
        self.permits = permits
    }

    public func withPermit<T>(_ operation: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if permits > 0 {
                permits -= 1
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    private func release() {
        lock.lock()
        if !waiters.isEmpty {
            let continuation = waiters.removeFirst()
            lock.unlock()
            continuation.resume()
            return
        }
        permits += 1
        lock.unlock()
    }
}

