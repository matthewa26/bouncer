import XCTest
import Foundation
@testable import BouncerCore

final class ParallelMapTests: XCTestCase {
    private struct Failure: Error, Equatable {
        let index: Int
    }

    /// Counts how many transforms run at once, and the most that ever did.
    private final class Overlap: @unchecked Sendable {
        private let lock = NSLock()
        private var running = 0
        private(set) var peak = 0

        func enter() { lock.withLock { running += 1; peak = max(peak, running) } }
        func leave() { lock.withLock { running -= 1 } }
    }

    func testKeepsInputOrderWhateverOrderItemsFinishIn() throws {
        let items = Array(0..<200)
        let mapped = try ParallelMap(jobs: 8).map(items) { item -> Int in
            if item % 7 == 0 { Thread.sleep(forTimeInterval: 0.001) }
            return item * 2
        }
        XCTAssertEqual(mapped, items.map { $0 * 2 })
    }

    func testRethrowsTheEarliestFailingItemsErrorEveryTime() {
        for _ in 0..<20 {
            XCTAssertThrowsError(try ParallelMap(jobs: 8).map(Array(0..<100)) { item -> Int in
                if item == 90 { throw Failure(index: item) }
                if item == 30 { Thread.sleep(forTimeInterval: 0.002); throw Failure(index: item) }
                return item
            }) { XCTAssertEqual($0 as? Failure, Failure(index: 30)) }
        }
    }

    /// Records the order items were transformed in, and whether each ran on the main thread.
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var order: [Int] = []
        private(set) var allOnMain = true

        func record(_ item: Int) { lock.withLock { order.append(item); allOnMain = allOnMain && Thread.isMainThread } }
    }

    func testOneJobRunsInTurnOnTheCallingThread() throws {
        XCTAssertTrue(Thread.isMainThread)
        let calls = Calls()
        _ = try ParallelMap(jobs: 1).map(Array(0..<10)) { item -> Int in
            calls.record(item)
            return item
        }
        XCTAssertEqual(calls.order, Array(0..<10))
        XCTAssertTrue(calls.allOnMain)
    }

    func testRunsSeveralItemsAtOnceWithSeveralJobs() throws {
        let overlap = Overlap()
        _ = try ParallelMap(jobs: 4).map(Array(0..<16)) { item -> Int in
            overlap.enter()
            Thread.sleep(forTimeInterval: 0.01)
            overlap.leave()
            return item
        }
        XCTAssertGreaterThan(overlap.peak, 1)
        XCTAssertLessThanOrEqual(overlap.peak, 4)
    }

    func testHandlesEmptyAndSingleItemLists() throws {
        XCTAssertEqual(try ParallelMap(jobs: 8).map([Int]()) { $0 }, [])
        XCTAssertEqual(try ParallelMap(jobs: 8).map([5]) { $0 + 1 }, [6])
    }
}
