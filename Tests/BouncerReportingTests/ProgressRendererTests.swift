import XCTest
import Foundation
import BouncerCore
@testable import BouncerReporting

final class ProgressRendererTests: XCTestCase {
    /// A clock the test moves by hand, and a sink that keeps everything written.
    private final class Harness: @unchecked Sendable {
        private let lock = NSLock()
        private var time = Duration.zero
        private var written: [String] = []

        var output: [String] { lock.lock(); defer { lock.unlock() }; return written }
        var text: String { output.joined() }
        func now() -> Duration { lock.lock(); defer { lock.unlock() }; return time }
        func advance(_ by: Duration) { lock.lock(); time += by; lock.unlock() }
        func write(_ text: String) { lock.lock(); written.append(text); lock.unlock() }
    }

    private let root = URL(fileURLWithPath: "/repo")
    private let clear = "\r\u{1B}[2K"

    private func renderer(
        _ style: ProgressStyle, verbose: Bool = false, width: Int = 80
    ) -> (ProgressRenderer, Harness) {
        let harness = Harness()
        var settings = ProgressRenderer.Settings(style: style)
        settings.verbose = verbose
        settings.root = root
        settings.width = width
        settings.analyzerNames = [.swift: "SwiftSyntaxAnalyzer"]
        let renderer = ProgressRenderer(
            settings: settings, write: { harness.write($0) }, now: { harness.now() }
        )
        return (renderer, harness)
    }

    private func file(_ name: String) -> URL { root.appendingPathComponent(name) }

    private func finished(_ name: String, findings: Int = 0, ms: Int = 5) -> AnalysisEvent {
        .fileFinished(file(name), language: .swift, findingCount: findings, duration: .milliseconds(ms))
    }

    // MARK: - Mode selection

    private func invocation(verbose: Bool = false, agent: Bool = false, terminal: Bool = false) -> ProgressInvocation {
        var invocation = ProgressInvocation()
        invocation.verbose = verbose
        invocation.isAgentInvocation = agent
        invocation.standardErrorIsTerminal = terminal
        return invocation
    }

    func testAutoIsOffForAgentsLiveOnATerminalAndPlainOtherwise() {
        XCTAssertEqual(ProgressMode.auto.style(for: invocation(agent: true, terminal: true)), .off)
        XCTAssertEqual(ProgressMode.auto.style(for: invocation(terminal: true)), .live)
        XCTAssertEqual(ProgressMode.auto.style(for: invocation()), .plain)
    }

    func testExplicitModesWinOverTheInvocation() {
        XCTAssertEqual(ProgressMode.live.style(for: invocation(agent: true)), .live)
        XCTAssertEqual(ProgressMode.plain.style(for: invocation(terminal: true)), .plain)
        XCTAssertEqual(ProgressMode.off.style(for: invocation(terminal: true)), .off)
    }

    func testVerboseForcesPlainLines() {
        XCTAssertEqual(ProgressMode.live.style(for: invocation(verbose: true, terminal: true)), .plain)
        XCTAssertEqual(ProgressMode.auto.style(for: invocation(verbose: true, terminal: true)), .plain)
        XCTAssertEqual(ProgressMode.auto.style(for: invocation(verbose: true, agent: true)), .plain)
    }

    // MARK: - Plain

    func testPlainPrintsOneLinePerPhaseStartAndFinish() {
        let (renderer, harness) = renderer(.plain)
        renderer.handle(.phaseStarted(.analyzeFiles, total: 12_345))
        renderer.handle(.fileStarted(file("a.swift")))
        renderer.handle(finished("a.swift"))
        renderer.handle(.phaseFinished(.analyzeFiles, duration: .milliseconds(41_200)))
        renderer.handle(.phaseStarted(.projectRules, total: nil))
        renderer.handle(.note("project index: 1 reused"))
        renderer.handle(.phaseFinished(.projectRules, duration: .seconds(2)))
        renderer.finish()
        XCTAssertEqual(harness.output, [
            "[bouncer] analyzing 12,345 files...\n",
            "[bouncer] analyzed 1 file in 41.2s\n",
            "[bouncer] running project rules...\n",
            "[bouncer] project index: 1 reused\n",
            "[bouncer] ran project rules in 2.0s\n"
        ])
    }

    func testPlainHeartbeatsAtEachTenthOnlyWhenSpacedOut() {
        let (renderer, harness) = renderer(.plain)
        renderer.handle(.phaseStarted(.analyzeFiles, total: 10))
        renderer.handle(finished("a.swift"))
        XCTAssertEqual(harness.output.count, 1, "a tenth done, but under 5s since the last line")
        harness.advance(.seconds(6))
        renderer.handle(.fileStarted(file("b.swift")))
        renderer.handle(finished("b.swift"))
        XCTAssertEqual(
            harness.output.last, "[bouncer] still analyzing: 2 of 10 files (20%), 6.0s elapsed; at b.swift\n"
        )
        renderer.handle(finished("c.swift"))
        XCTAssertEqual(harness.output.count, 2, "the next tenth comes too soon after the last heartbeat")
    }

    func testPlainTickPrintsAHeartbeatAfterAQuietSpell() {
        let (renderer, harness) = renderer(.plain)
        renderer.handle(.phaseStarted(.projectIndex, total: 3))
        renderer.handle(.fileStarted(file("slow.swift")))
        harness.advance(.seconds(29))
        renderer.tick()
        XCTAssertEqual(harness.output.count, 1)
        harness.advance(.seconds(1))
        renderer.tick()
        XCTAssertEqual(
            harness.output.last, "[bouncer] still indexing: 0 of 3 project files (0%), 30.0s elapsed; at slow.swift\n"
        )
    }

    func testOffWritesNothing() {
        let (renderer, harness) = renderer(.off, width: 40)
        renderer.handle(.phaseStarted(.analyzeFiles, total: 1))
        renderer.handle(finished("a.swift"))
        renderer.tick()
        renderer.finish()
        XCTAssertTrue(harness.output.isEmpty)
    }

    // MARK: - Verbose

    func testVerboseLogsEveryFileWithATimestamp() {
        let (renderer, harness) = renderer(.plain, verbose: true)
        renderer.log("config: repo /repo/.bouncer (found)")
        harness.advance(.milliseconds(1_500))
        renderer.handle(.phaseStarted(.analyzeFiles, total: 2))
        renderer.handle(finished("a.swift", findings: 3, ms: 12))
        renderer.handle(.fileFinished(file("x.sh"), language: .bash, findingCount: 1, duration: .milliseconds(2)))
        XCTAssertEqual(harness.output, [
            "[bouncer +0.000s] config: repo /repo/.bouncer (found)\n",
            "[bouncer +1.500s] analyzing 2 files...\n",
            "[bouncer +1.500s] analyzed a.swift (swift, SwiftSyntaxAnalyzer): 3 findings in 12ms\n",
            "[bouncer +1.500s] analyzed x.sh (bash, heuristic): 1 finding in 2ms\n"
        ])
    }

    func testLogIsSilentWithoutVerbose() {
        let (renderer, harness) = renderer(.plain)
        renderer.log("config: repo")
        XCTAssertTrue(harness.output.isEmpty)
    }

    // MARK: - Live

    func testLiveRedrawsAtMostTenTimesASecond() {
        let (renderer, harness) = renderer(.live)
        renderer.handle(.phaseStarted(.analyzeFiles, total: 100))
        for index in 0..<50 { renderer.handle(.fileStarted(file("\(index).swift"))) }
        XCTAssertEqual(harness.output.count, 1, "the phase start draws; the burst of files that follows doesn't")
        harness.advance(.milliseconds(99))
        renderer.tick()
        XCTAssertEqual(harness.output.count, 1)
        harness.advance(.milliseconds(1))
        renderer.tick()
        XCTAssertEqual(harness.output.count, 2)
    }

    func testLiveLineShowsBarCountsPhaseFileAndClock() {
        let (renderer, harness) = renderer(.live)
        renderer.handle(.phaseStarted(.analyzeFiles, total: 4))
        renderer.handle(finished("a.swift"))
        harness.advance(.seconds(72))
        renderer.handle(.fileStarted(file("Sources/b.swift")))
        XCTAssertEqual(
            harness.output.last, clear + "[#####---------------] 1/4 25% analyzing  Sources/b.swift  1:12"
        )
    }

    func testLiveLineFitsTheTerminalByShorteningThePath() {
        let (renderer, harness) = renderer(.live, width: 60)
        renderer.handle(.phaseStarted(.analyzeFiles, total: 4))
        harness.advance(.seconds(1))
        renderer.handle(.fileStarted(file("Sources/Deeply/Nested/Directory/Structure/File.swift")))
        let line = String(harness.output.last?.dropFirst(clear.count) ?? "")
        XCTAssertEqual(line.count, 59)
        XCTAssertTrue(line.contains("...") && line.hasSuffix("ile.swift  0:01"), line)
    }

    func testLiveLineIsClearedAtFinishAndForHookOutput() {
        let (renderer, harness) = renderer(.live)
        renderer.handle(.phaseStarted(.analyzeFiles, total: 1))
        renderer.handle(.phaseFinished(.analyzeFiles, duration: .zero))
        renderer.handle(.phaseStarted(.postCheckHooks, total: nil))
        XCTAssertEqual(harness.output.last, clear, "hook output gets a clean line")
        harness.advance(.seconds(1))
        renderer.tick()
        XCTAssertEqual(harness.output.last, clear, "nothing redraws over a running hook")
        renderer.handle(.phaseFinished(.postCheckHooks, duration: .zero))
        renderer.handle(.phaseStarted(.report, total: nil))
        XCTAssertTrue(harness.output.last?.hasPrefix(clear + "rendering the report") == true)
        renderer.finish()
        XCTAssertEqual(harness.output.last, clear)
        renderer.handle(.phaseStarted(.report, total: nil))
        XCTAssertEqual(harness.output.last, clear, "nothing is written after finish")
    }

    func testLiveModeDoesNotPrintPlainLines() {
        let (renderer, harness) = renderer(.live)
        renderer.handle(.phaseStarted(.baseline, total: nil))
        renderer.handle(.note("the baseline accepted 3 finding(s)"))
        renderer.handle(.phaseFinished(.baseline, duration: .zero))
        renderer.finish()
        XCTAssertFalse(harness.text.contains("\n"))
    }

    // MARK: - Formatting

    func testFormatsCountsAndDurations() {
        XCTAssertEqual(ProgressText.grouped(0), "0")
        XCTAssertEqual(ProgressText.grouped(999), "999")
        XCTAssertEqual(ProgressText.grouped(1_234_567), "1,234,567")
        XCTAssertEqual(ProgressText.seconds(.milliseconds(12)), "12ms")
        XCTAssertEqual(ProgressText.seconds(.seconds(185)), "3m 05s")
        XCTAssertEqual(ProgressText.seconds(.seconds(3_720)), "1h 02m")
        XCTAssertEqual(ProgressText.clock(.seconds(3_723)), "1:02:03")
    }
}
