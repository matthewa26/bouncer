import ArgumentParser
import Foundation
import BouncerXcode

extension XcodeScope: ExpressibleByArgument {}
extension XcodeFailOn: ExpressibleByArgument {}

/// Adds Bouncer to an Xcode project as a Run Script build phase, or takes it out again.
struct XcodeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcode", abstract: "Run Bouncer on every Xcode build, with findings shown inline.",
        subcommands: [Install.self, Uninstall.self]
    )

    /// The help text for `--project`.
    static let projectHelp: ArgumentHelp = "The .xcodeproj to edit. (default: the only one in the current directory)"

    /// Stops with an explanation when this build can't edit Xcode projects.
    ///
    /// - Throws: `ExitCode.failure` on Linux and Windows.
    static func requireSupport() throws {
        guard !XcodeIntegration.isSupported else { return }
        FileHandle.standardError.write(Data("bouncer xcode is only available on macOS.\n".utf8))
        throw ExitCode.failure
    }

    /// The directory `bouncer xcode` was run from, which `--project` is resolved against.
    static var currentDirectory: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    #if canImport(XcodeProj)
    /// Opens the project `--project` names, or the only one in the current directory.
    ///
    /// - Parameter path: The `--project` value, if given.
    /// - Returns: An editor for the project.
    /// - Throws: An `XcodeIntegrationError` if no single project is found or it can't be read.
    static func openProject(_ path: String?) throws -> XcodeProjectEditor {
        try XcodeProjectEditor(projectURL: XcodeProjectLocator.locate(explicitPath: path, in: currentDirectory))
    }
    #endif
}

extension XcodeCommand {
    /// Adds the `Bouncer` Run Script phase to the chosen targets, or updates the one already there.
    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a Bouncer Run Script phase before Compile Sources.",
            discussion: "Re-running it updates the existing phase. project.pbxproj is backed up to "
                + "project.pbxproj.bouncer-backup the first time."
        )

        @Option(help: XcodeCommand.projectHelp)
        var project: String?

        @Option(name: .customLong("target"), help: "A target to add the phase to; repeat for several.")
        var targets: [String] = []

        @Option(help: "review checks everything under $SRCROOT, check only the staged files.")
        var scope: XcodeScope = .review

        @Option(help: "Which findings fail the build.")
        var failOn: XcodeFailOn = .error

        @Flag(help: "Turn off ENABLE_USER_SCRIPT_SANDBOXING for the chosen targets without asking.")
        var disableScriptSandboxing = false

        /// Edits the project and saves it.
        ///
        /// - Throws: `ExitCode.failure` off macOS, or an `XcodeIntegrationError`, `ValidationError`, or file error.
        func run() throws {
            try XcodeCommand.requireSupport()
            #if canImport(XcodeProj)
            let editor = try XcodeCommand.openProject(project)
            let names = targets.isEmpty ? try XcodeTargetPicker.choose(from: editor) : targets
            let changes = try editor.install(BouncerBuildScript(scope: scope, failOn: failOn), into: names)
            try XcodeSandboxing(editor: editor, preapproved: disableScriptSandboxing).review(names)
            try editor.save()
            report(changes, projectURL: editor.projectURL)
            #endif
        }

        #if canImport(XcodeProj)
        /// Prints what changed in each target and where the backup is.
        ///
        /// - Parameters:
        ///   - changes: What happened in each target.
        ///   - projectURL: The edited project.
        private func report(_ changes: [(String, PhaseChange)], projectURL: URL) {
            for (target, change) in changes {
                print("\(change == .added ? "Added" : "Updated") the Bouncer phase in \(target).")
            }
            print("Scope: \(scope.rawValue); the build fails on: \(failOn.rawValue).")
            print("Backup: \(projectURL.appendingPathComponent(XcodeProjectEditor.backupName).path)")
        }
        #endif
    }

    /// Removes the `Bouncer` Run Script phases `install` added.
    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove the Bouncer Run Script phase. The backup is left in place."
        )

        @Option(help: XcodeCommand.projectHelp)
        var project: String?

        @Option(name: .customLong("target"), help: "A target to remove it from; repeat for several. (default: all)")
        var targets: [String] = []

        /// Removes the phases and saves the project if any were found.
        ///
        /// - Throws: `ExitCode.failure` off macOS, or an `XcodeIntegrationError` or file error.
        func run() throws {
            try XcodeCommand.requireSupport()
            #if canImport(XcodeProj)
            let editor = try XcodeCommand.openProject(project)
            let removed = try editor.uninstall(from: targets.isEmpty ? nil : targets)
            if !removed.isEmpty { try editor.save() }
            try report(removed, editor: editor)
            #endif
        }

        #if canImport(XcodeProj)
        /// Prints which targets lost their phase, and any of them whose script sandboxing is still off.
        ///
        /// - Parameters:
        ///   - removed: The targets a phase was removed from.
        ///   - editor: The edited project.
        /// - Throws: `XcodeIntegrationError.unknownTargets`, which can't happen for targets just edited.
        private func report(_ removed: [String], editor: XcodeProjectEditor) throws {
            guard !removed.isEmpty else {
                return print("No Bouncer phase found in \(editor.projectURL.lastPathComponent).")
            }
            removed.forEach { print("Removed the Bouncer phase from \($0).") }
            XcodeSandboxing.noteDisabled(try editor.sandboxingDisabledTargets(removed))
        }
        #endif
    }
}
