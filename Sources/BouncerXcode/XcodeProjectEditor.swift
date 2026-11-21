#if canImport(XcodeProj)
import Foundation
import PathKit
import XcodeProj

/// Opens an Xcode project and adds, updates, or removes Bouncer's Run Script phase in its native targets.
///
/// Nothing is written until `save()`, which backs up `project.pbxproj` first.
public final class XcodeProjectEditor {
    /// The `.xcodeproj` bundle being edited.
    public let projectURL: URL

    /// The parsed project.
    private let project: XcodeProj

    /// The build setting that confines Run Script phases to their declared inputs and outputs.
    public static let sandboxingSetting = "ENABLE_USER_SCRIPT_SANDBOXING"

    /// The name of the backup `save()` writes beside `project.pbxproj`.
    public static let backupName = "project.pbxproj.bouncer-backup"

    /// Product types that hold tests, which the default target choice leaves out.
    private static var testProductTypes: [PBXProductType] { [.unitTestBundle, .uiTestBundle, .ocUnitTestBundle] }

    /// Opens a project.
    ///
    /// - Parameter projectURL: The `.xcodeproj` bundle.
    /// - Throws: `XcodeIntegrationError.unreadableProject` if it can't be read or parsed.
    public init(projectURL: URL) throws {
        self.projectURL = projectURL
        do {
            project = try XcodeProj(pathString: projectURL.path)
        } catch {
            throw XcodeIntegrationError.unreadableProject(path: projectURL.path, reason: "\(error)")
        }
    }

    /// The project's native targets, in the order Xcode lists them.
    private var nativeTargets: [PBXNativeTarget] {
        (project.pbxproj.rootObject?.targets ?? []).compactMap { $0 as? PBXNativeTarget }
    }

    /// Every native target's name, in the order Xcode lists them.
    public var targetNames: [String] { nativeTargets.map(\.name) }

    /// The targets `install` picks when asked for the default: every app, framework, library, and tool target,
    /// leaving out test bundles.
    public var defaultTargetNames: [String] {
        nativeTargets.filter { target in target.productType.map { !Self.testProductTypes.contains($0) } ?? true }
            .map(\.name)
    }

    /// The targets with a Bouncer phase.
    public var installedTargetNames: [String] {
        nativeTargets.filter { !bouncerPhases(of: $0).isEmpty }.map(\.name)
    }

    /// Adds the Bouncer phase to each target, or rewrites the one already there.
    ///
    /// - Parameters:
    ///   - script: The script the phase runs.
    ///   - names: The targets to install into.
    /// - Returns: What happened in each target, in the order given.
    /// - Throws: `XcodeIntegrationError.unknownTargets` if a name isn't a native target.
    public func install(_ script: BouncerBuildScript, into names: [String]) throws -> [(String, PhaseChange)] {
        try targets(named: names).map { target in (target.name, install(script.text, into: target)) }
    }

    /// Removes the Bouncer phases from the given targets, or from every target.
    ///
    /// - Parameter names: The targets to remove it from, or `nil` for all of them.
    /// - Returns: The targets a phase was removed from.
    /// - Throws: `XcodeIntegrationError.unknownTargets` if a name isn't a native target.
    public func uninstall(from names: [String]?) throws -> [String] {
        let chosen = try names.map(targets(named:)) ?? nativeTargets
        return chosen.filter(removeBouncerPhases).map(\.name)
    }

    /// Lists the given targets that have Run Script sandboxing on in any build configuration.
    ///
    /// A target's own setting wins over the project's; unset in both means off, as Xcode builds it.
    ///
    /// - Parameter names: The targets to check.
    /// - Returns: The sandboxed targets' names.
    /// - Throws: `XcodeIntegrationError.unknownTargets` if a name isn't a native target.
    public func sandboxedTargets(_ names: [String]) throws -> [String] {
        try targets(named: names).filter { target in
            configurations(of: target).contains { sandboxing(in: $0) == "YES" }
        }.map(\.name)
    }

    /// Lists the given targets whose own build settings turn Run Script sandboxing off.
    ///
    /// - Parameter names: The targets to check.
    /// - Returns: Those targets' names.
    /// - Throws: `XcodeIntegrationError.unknownTargets` if a name isn't a native target.
    public func sandboxingDisabledTargets(_ names: [String]) throws -> [String] {
        try targets(named: names).filter { target in
            configurations(of: target).contains { $0.buildSettings[Self.sandboxingSetting]?.stringValue == "NO" }
        }.map(\.name)
    }

    /// Turns Run Script sandboxing off in every build configuration of the given targets, and nowhere else.
    ///
    /// - Parameter names: The targets to change.
    /// - Throws: `XcodeIntegrationError.unknownTargets` if a name isn't a native target.
    public func disableScriptSandboxing(_ names: [String]) throws {
        for target in try targets(named: names) {
            configurations(of: target).forEach { $0.buildSettings[Self.sandboxingSetting] = .string("NO") }
        }
    }

    /// Writes the project, after copying `project.pbxproj` to `project.pbxproj.bouncer-backup` if no backup
    /// exists yet, so the backup always holds the project as it was before Bouncer first changed it.
    ///
    /// - Throws: If the backup or the project can't be written.
    public func save() throws {
        let pbxprojURL = projectURL.appendingPathComponent("project.pbxproj")
        let backup = projectURL.appendingPathComponent(Self.backupName)
        if !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: pbxprojURL, to: backup)
        }
        try project.pbxproj.write(path: Path(pbxprojURL.path), override: true)
    }

    /// Finds native targets by name.
    ///
    /// - Parameter names: The names to find.
    /// - Returns: The targets, in the order given.
    /// - Throws: `XcodeIntegrationError.unknownTargets` naming every name that isn't a native target.
    private func targets(named names: [String]) throws -> [PBXNativeTarget] {
        let all = nativeTargets
        let missing = names.filter { name in !all.contains { $0.name == name } }
        guard missing.isEmpty else {
            throw XcodeIntegrationError.unknownTargets(requested: missing, available: all.map(\.name))
        }
        return names.compactMap { name in all.first { $0.name == name } }
    }

    /// Adds the Bouncer phase to one target before its Compile Sources phase, or rewrites the existing one.
    ///
    /// - Parameters:
    ///   - script: The script text.
    ///   - target: The target.
    /// - Returns: Whether the phase was added or updated.
    private func install(_ script: String, into target: PBXNativeTarget) -> PhaseChange {
        if let existing = bouncerPhases(of: target).first {
            Self.configure(existing, script: script)
            return .updated
        }
        insertPhase(script, into: target)
        return .added
    }

    /// Adds a new Bouncer phase to a target, right before its Compile Sources phase, or first if it has none.
    ///
    /// - Parameters:
    ///   - script: The script text.
    ///   - target: The target.
    private func insertPhase(_ script: String, into target: PBXNativeTarget) {
        let phase = PBXShellScriptBuildPhase()
        Self.configure(phase, script: script)
        project.pbxproj.add(object: phase)
        let index = target.buildPhases.firstIndex { $0.buildPhase == .sources } ?? 0
        target.buildPhases.insert(phase, at: index)
    }

    /// Sets a phase's name, script, and run conditions, so it runs on every build, not only when its declared
    /// inputs change.
    ///
    /// - Parameters:
    ///   - phase: The phase.
    ///   - script: The script text.
    private static func configure(_ phase: PBXShellScriptBuildPhase, script: String) {
        phase.name = BouncerBuildScript.phaseName
        phase.shellPath = "/bin/sh"
        phase.shellScript = script
        phase.alwaysOutOfDate = true
        phase.runOnlyForDeploymentPostprocessing = false
        phase.showEnvVarsInLog = false
    }

    /// Finds the Run Script phases Bouncer added to a target.
    ///
    /// - Parameter target: The target.
    /// - Returns: Its phases carrying Bouncer's marker.
    private func bouncerPhases(of target: PBXNativeTarget) -> [PBXShellScriptBuildPhase] {
        target.buildPhases.compactMap { $0 as? PBXShellScriptBuildPhase }
            .filter { BouncerBuildScript.isBouncerScript($0.shellScript) }
    }

    /// Removes a target's Bouncer phases from it and from the project.
    ///
    /// - Parameter target: The target.
    /// - Returns: Whether any were removed.
    private func removeBouncerPhases(from target: PBXNativeTarget) -> Bool {
        let phases = bouncerPhases(of: target)
        target.buildPhases.removeAll { phase in phases.contains { $0 === phase } }
        phases.forEach(project.pbxproj.delete)
        return !phases.isEmpty
    }

    /// Lists a target's build configurations.
    ///
    /// - Parameter target: The target.
    /// - Returns: Its configurations, such as Debug and Release.
    private func configurations(of target: PBXNativeTarget) -> [XCBuildConfiguration] {
        target.buildConfigurationList?.buildConfigurations ?? []
    }

    /// Reads the sandboxing setting a target configuration builds with: its own, else the project's
    /// configuration of the same name.
    ///
    /// - Parameter configuration: A target's build configuration.
    /// - Returns: `YES`, `NO`, or `nil` when neither sets it.
    private func sandboxing(in configuration: XCBuildConfiguration) -> String? {
        if let own = configuration.buildSettings[Self.sandboxingSetting]?.stringValue { return own }
        let projectConfigurations = project.pbxproj.rootObject?.buildConfigurationList?.buildConfigurations ?? []
        let match = projectConfigurations.first { $0.name == configuration.name }
        return match?.buildSettings[Self.sandboxingSetting]?.stringValue
    }
}
#endif
