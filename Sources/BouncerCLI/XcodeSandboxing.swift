#if canImport(XcodeProj)
import Foundation
import BouncerConfig
import BouncerXcode

/// Deals with Xcode's user script sandboxing, which stops the Bouncer phase from reading the sources it checks.
///
/// Under `ENABLE_USER_SCRIPT_SANDBOXING`, a Run Script phase may only read the files it declares as inputs, one
/// by one: a declared folder grants the folder entry alone, not what's inside it. Bouncer walks the source tree
/// and runs git, so no practical declaration covers it, and sandboxing has to be off for the targets running it.
/// It's never turned off silently: `--disable-script-sandboxing` or a yes at the prompt is required.
struct XcodeSandboxing {
    /// The opened project.
    let editor: XcodeProjectEditor
    /// Whether `--disable-script-sandboxing` already gave permission.
    let preapproved: Bool

    /// Explains the problem for any sandboxed targets, then turns sandboxing off for them if permitted, or says
    /// how to do it by hand.
    ///
    /// - Parameter names: The targets the phase was installed into.
    /// - Throws: `PromptError.endOfInput` if input ends at the prompt, or `XcodeIntegrationError.unknownTargets`.
    func review(_ names: [String]) throws {
        let sandboxed = try editor.sandboxedTargets(names)
        guard !sandboxed.isEmpty else { return }
        Self.explain(sandboxed)
        guard try approved() else { return Self.printManualSteps() }
        try editor.disableScriptSandboxing(sandboxed)
        print("Set \(XcodeProjectEditor.sandboxingSetting) = NO for \(sandboxed.joined(separator: ", ")).")
    }

    /// Asks for permission to turn sandboxing off, unless it was given up front or there's no one to ask.
    ///
    /// - Returns: Whether to turn it off.
    /// - Throws: `PromptError.endOfInput` if input ends at the prompt.
    private func approved() throws -> Bool {
        if preapproved { return true }
        guard Terminal.standardInputIsInteractive else { return false }
        return try Prompt.standard.yesNo("Turn script sandboxing off for these targets?", default: false)
    }

    /// Says why sandboxing gets in the way.
    ///
    /// - Parameter targets: The sandboxed targets.
    private static func explain(_ targets: [String]) {
        print("""
            User script sandboxing (\(XcodeProjectEditor.sandboxingSetting)) is on for \
            \(targets.joined(separator: ", ")).
            A sandboxed Run Script phase can only read files it lists as inputs one by one (a listed folder doesn't \
            cover what's inside it), so Bouncer couldn't read your sources or run git: it would report nothing, or \
            fail the build with sandbox errors.
            """)
    }

    /// Says how to turn sandboxing off without Bouncer's help.
    private static func printManualSteps() {
        print("""
            Left sandboxing on. To let the Bouncer phase run, either re-run with --disable-script-sandboxing, or in \
            Xcode open each target's Build Settings and set User Script Sandboxing to No.
            """)
    }

    /// Mentions targets whose sandboxing is off, after the phase is removed, in case only Bouncer needed it off.
    ///
    /// - Parameter targets: The targets with `ENABLE_USER_SCRIPT_SANDBOXING = NO`.
    static func noteDisabled(_ targets: [String]) {
        guard !targets.isEmpty else { return }
        print("""
            Script sandboxing is still off for \(targets.joined(separator: ", ")). If it was only turned off for \
            Bouncer, set User Script Sandboxing back to Yes in those targets' Build Settings.
            """)
    }
}
#endif
