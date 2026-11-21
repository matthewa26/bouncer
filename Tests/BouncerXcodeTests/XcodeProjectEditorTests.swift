#if canImport(XcodeProj)
import XCTest
import Foundation
import XcodeProj
@testable import BouncerXcode

final class XcodeProjectEditorTests: XCTestCase {
    private var directory: URL!
    private let script = BouncerBuildScript(scope: .review, failOn: .error)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("xcode-editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeProject(projectSettings: BuildSettings = [:]) throws -> URL {
        try FixtureProject.make(
            in: directory,
            targets: [("App", .application), ("Kit", .framework), ("AppTests", .unitTestBundle)],
            projectSettings: projectSettings
        )
    }

    /// Reopens the project from disk and lists one target's phases as (kind, name, script).
    private func phases(_ projectURL: URL, target: String) throws -> [(BuildPhase, String?, String?)] {
        let project = try XcodeProj(pathString: projectURL.path)
        let native = try XCTUnwrap(project.pbxproj.nativeTargets.first { $0.name == target })
        return native.buildPhases.map { phase in
            let shell = phase as? PBXShellScriptBuildPhase
            return (phase.buildPhase, shell?.name, shell?.shellScript)
        }
    }

    private func pbxproj(_ projectURL: URL) throws -> Data {
        try Data(contentsOf: projectURL.appendingPathComponent("project.pbxproj"))
    }

    func testDefaultTargetsLeaveOutTestBundles() throws {
        let editor = try XcodeProjectEditor(projectURL: try makeProject())
        XCTAssertEqual(editor.targetNames, ["App", "Kit", "AppTests"])
        XCTAssertEqual(editor.defaultTargetNames, ["App", "Kit"])
    }

    func testInstallAddsThePhaseRightBeforeCompileSources() throws {
        let url = try makeProject()
        let editor = try XcodeProjectEditor(projectURL: url)
        let changes = try editor.install(script, into: ["App"])
        try editor.save()
        XCTAssertEqual(changes.map(\.0), ["App"])
        XCTAssertEqual(changes.map(\.1), [.added])
        let appPhases = try phases(url, target: "App")
        XCTAssertEqual(appPhases.map(\.0), [.frameworks, .runScript, .sources])
        XCTAssertEqual(appPhases[1].1, "Bouncer")
        XCTAssertEqual(appPhases[1].2, script.text)
        XCTAssertEqual(try phases(url, target: "Kit").map(\.0), [.frameworks, .sources])
    }

    func testInstalledPhaseRunsOnEveryBuild() throws {
        let url = try makeProject()
        let editor = try XcodeProjectEditor(projectURL: url)
        _ = try editor.install(script, into: ["App"])
        try editor.save()
        let project = try XcodeProj(pathString: url.path)
        let phase = try XCTUnwrap(project.pbxproj.shellScriptBuildPhases.first)
        XCTAssertTrue(phase.alwaysOutOfDate)
        XCTAssertFalse(phase.runOnlyForDeploymentPostprocessing)
        XCTAssertTrue(BouncerBuildScript.isBouncerScript(phase.shellScript))
    }

    func testInstallingTwiceUpdatesTheOnePhase() throws {
        let url = try makeProject()
        _ = try saveInstall(url, script: script)
        let changes = try saveInstall(url, script: BouncerBuildScript(scope: .check, failOn: .never))
        XCTAssertEqual(changes.map(\.1), [.updated])
        let scripts = try phases(url, target: "App").compactMap(\.2)
        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].contains("bouncer check --format xcode"))
        XCTAssertEqual(try XcodeProj(pathString: url.path).pbxproj.shellScriptBuildPhases.count, 1)
    }

    private func saveInstall(_ url: URL, script: BouncerBuildScript) throws -> [(String, PhaseChange)] {
        let editor = try XcodeProjectEditor(projectURL: url)
        let changes = try editor.install(script, into: ["App"])
        try editor.save()
        return changes
    }

    func testUnknownTargetsAreRejected() throws {
        let editor = try XcodeProjectEditor(projectURL: try makeProject())
        XCTAssertThrowsError(try editor.install(script, into: ["App", "Nope"])) { error in
            XCTAssertEqual(
                error as? XcodeIntegrationError,
                .unknownTargets(requested: ["Nope"], available: ["App", "Kit", "AppTests"])
            )
        }
    }

    func testUninstallRemovesOnlyBouncerPhases() throws {
        let url = try makeProject()
        _ = try saveInstall(url, script: script)
        let editor = try XcodeProjectEditor(projectURL: url)
        XCTAssertEqual(try editor.uninstall(from: nil), ["App"])
        try editor.save()
        XCTAssertEqual(try phases(url, target: "App").map(\.0), [.frameworks, .sources])
        XCTAssertTrue(try XcodeProj(pathString: url.path).pbxproj.shellScriptBuildPhases.isEmpty)
        XCTAssertEqual(try XcodeProjectEditor(projectURL: url).uninstall(from: nil), [])
    }

    func testBackupIsWrittenOnceBeforeTheFirstChange() throws {
        let url = try makeProject()
        let original = try pbxproj(url)
        _ = try saveInstall(url, script: script)
        _ = try saveInstall(url, script: BouncerBuildScript(scope: .check, failOn: .warning))
        let backup = try Data(contentsOf: url.appendingPathComponent(XcodeProjectEditor.backupName))
        XCTAssertEqual(backup, original)
        XCTAssertNotEqual(try pbxproj(url), original)
    }

    func testUninstallAfterInstallRestoresTheOriginalProject() throws {
        let url = try makeProject()
        let original = try pbxproj(url)
        let before = try ["App", "Kit", "AppTests"].map { try phases(url, target: $0).map(\.0) }
        _ = try saveInstall(url, script: script)
        let editor = try XcodeProjectEditor(projectURL: url)
        _ = try editor.uninstall(from: nil)
        try editor.save()
        XCTAssertEqual(try ["App", "Kit", "AppTests"].map { try phases(url, target: $0).map(\.0) }, before)
        XCTAssertEqual(try pbxproj(url), original, "an XcodeProj-written project round-trips byte for byte")
    }

    func testSandboxingIsReadFromTheTargetThenTheProject() throws {
        let url = try makeProject(projectSettings: [XcodeProjectEditor.sandboxingSetting: .string("YES")])
        let editor = try XcodeProjectEditor(projectURL: url)
        XCTAssertEqual(try editor.sandboxedTargets(["App", "Kit"]), ["App", "Kit"])
        try editor.disableScriptSandboxing(["App"])
        XCTAssertEqual(try editor.sandboxedTargets(["App", "Kit"]), ["Kit"])
        XCTAssertEqual(try editor.sandboxingDisabledTargets(["App", "Kit", "AppTests"]), ["App"])
    }

    func testDisablingSandboxingChangesOnlyTheChosenTargets() throws {
        let url = try makeProject(projectSettings: [XcodeProjectEditor.sandboxingSetting: .string("YES")])
        let editor = try XcodeProjectEditor(projectURL: url)
        try editor.disableScriptSandboxing(["Kit"])
        try editor.save()
        let project = try XcodeProj(pathString: url.path)
        for target in project.pbxproj.nativeTargets {
            let values = target.buildConfigurationList?.buildConfigurations
                .map { $0.buildSettings[XcodeProjectEditor.sandboxingSetting]?.stringValue }
            XCTAssertEqual(values, target.name == "Kit" ? ["NO", "NO"] : [nil, nil], target.name)
        }
        let projectValues = project.pbxproj.rootObject?.buildConfigurationList?.buildConfigurations
            .map { $0.buildSettings[XcodeProjectEditor.sandboxingSetting]?.stringValue }
        XCTAssertEqual(projectValues, ["YES", "YES"])
    }

    func testUnsetSandboxingCountsAsOff() throws {
        let editor = try XcodeProjectEditor(projectURL: try makeProject())
        XCTAssertEqual(try editor.sandboxedTargets(["App", "Kit"]), [])
    }

    func testUnreadableProjectsThrowAnIntegrationError() {
        XCTAssertThrowsError(try XcodeProjectEditor(projectURL: directory.appendingPathComponent("Missing.xcodeproj"))) {
            guard case .unreadableProject = $0 as? XcodeIntegrationError else { return XCTFail("\($0)") }
        }
    }
}
#endif
