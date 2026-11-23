import Foundation

/// Maps a list on several threads at once, keeping the results in the list's order.
///
/// Each worker claims the next unclaimed index, so one slow item never holds up the rest. A failure stops new
/// claims, and the earliest failing item's error is rethrown: every item before it was claimed first, so it has
/// finished too, and the error is the one a sequential map would have thrown.
struct ParallelMap {
    /// How many threads to run at most; one maps in turn on the calling thread.
    let jobs: Int

    /// Transforms every item on up to `jobs` threads.
    ///
    /// - Parameters:
    ///   - items: The items.
    ///   - transform: Transforms one item; with more than one job, it's called from several threads at once.
    /// - Returns: The transformed items, in the items' order.
    /// - Throws: The earliest failing item's error.
    func map<Item: Sendable, Value: Sendable>(
        _ items: [Item], _ transform: @escaping @Sendable (Item) throws -> Value
    ) throws -> [Value] {
        let workers = min(jobs, items.count)
        guard workers > 1 else { return try items.map(transform) }
        let claims = ParallelClaims<Value>(count: items.count)
        WorkerThreads.start(workers) {
            while let index = claims.next() { claims.store(Result { try transform(items[index]) }, at: index) }
        }
        return try claims.values()
    }
}

/// Threads with a stack big enough for the recursion that parsing deeply nested code takes.
///
/// A thread's default stack depends on the platform: a Dispatch or Swift concurrency thread gets 512 KiB on
/// macOS, but only musl's 128 KiB in the static Linux build, which deeply nested code overflows. Analysis runs
/// on these threads instead, so every platform gets the same, generous stack.
enum WorkerThreads {
    /// Each thread's stack size: 64 MiB, reserved rather than committed, so unused stack costs no memory.
    static let stackSize = 64 << 20

    /// Runs a closure on several new threads at once and waits until every one returns.
    ///
    /// - Parameters:
    ///   - count: How many threads to start.
    ///   - body: The work each thread does.
    static func start(_ count: Int, _ body: @escaping @Sendable () -> Void) {
        let group = DispatchGroup()
        for _ in 0..<count {
            group.enter()
            let thread = Thread { body(); group.leave() }
            thread.stackSize = stackSize
            thread.start()
        }
        group.wait()
    }

    /// Runs a closure on a new thread and waits for it.
    ///
    /// - Parameter body: The work.
    /// - Returns: What it returned.
    /// - Throws: What it threw.
    static func call<Value: Sendable>(_ body: @escaping @Sendable () throws -> Value) throws -> Value {
        let claims = ParallelClaims<Value>(count: 1)
        start(1) { claims.store(Result { try body() }, at: 0) }
        return try claims.values()[0]
    }
}

/// One `ParallelMap.map` call's shared state: the next index to hand out, and each finished item's result.
///
/// It's unchecked because `lock` guards every mutable property, and a `Mutex` needs macOS 15.
// bouncer:disable-next-line swift-unchecked-sendable -- NSLock guards every stored property
private final class ParallelClaims<Value: Sendable>: @unchecked Sendable {
    /// Guards every stored property below.
    private let lock = NSLock()
    /// Each item's result, once it has one.
    private var results: [Result<Value, any Error>?]
    /// The next index to hand out.
    private var nextIndex = 0
    /// Whether an item has failed, which stops further claims.
    private var failed = false

    /// Creates the state for a list.
    ///
    /// - Parameter count: How many items the list has.
    init(count: Int) {
        results = Array(repeating: nil, count: count)
    }

    /// Claims the next item.
    ///
    /// - Returns: Its index, or `nil` once every item is claimed or one has failed.
    func next() -> Int? {
        lock.withLock {
            guard !failed, nextIndex < results.count else { return nil }
            defer { nextIndex += 1 }
            return nextIndex
        }
    }

    /// Keeps a claimed item's result, stopping further claims if it failed.
    ///
    /// - Parameters:
    ///   - result: The item's value or error.
    ///   - index: The item's index.
    func store(_ result: Result<Value, any Error>, at index: Int) {
        lock.withLock {
            results[index] = result
            if case .failure = result { failed = true }
        }
    }

    /// Collects the results once every worker has returned.
    ///
    /// - Returns: Every item's value, in order.
    /// - Throws: The earliest failing item's error; items after it may never have been claimed.
    func values() throws -> [Value] {
        try results.compactMap { try $0?.get() }
    }
}
