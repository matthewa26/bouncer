/// What the Xcode build phase analyzes: the staged files, as `bouncer check` does, or the whole source root,
/// as `bouncer review` does.
public enum XcodeScope: String, Sendable, CaseIterable {
    /// `bouncer check`: only the files staged in git.
    case check
    /// `bouncer review "$SRCROOT"`: every file under the project's source root.
    case review
}

/// Which findings fail the Xcode build.
public enum XcodeFailOn: String, Sendable, CaseIterable {
    /// Errors fail the build; warnings and notes only show.
    case error
    /// Errors and warnings fail the build.
    case warning
    /// Nothing fails the build; errors are shown as warnings.
    case never
}

/// What `install` did to one target's build phases.
public enum PhaseChange: String, Sendable, Equatable {
    /// A new `Bouncer` phase was added before Compile Sources.
    case added
    /// The existing `Bouncer` phase's script and settings were rewritten.
    case updated
}

/// The shell script the `Bouncer` Run Script phase runs, and how to recognize one Bouncer added.
public struct BouncerBuildScript: Sendable, Equatable {
    /// The name the phase shows in Xcode's Build Phases list.
    public static let phaseName = "Bouncer"

    /// The first line of every script Bouncer adds, which `install` and `uninstall` find it by.
    public static let marker = "# Added by 'bouncer xcode install'. Re-run it to update this phase, or run "
        + "'bouncer xcode uninstall' to remove it."

    /// Where Bouncer's install documentation lives, for the warning a build shows when it's missing.
    public static let installURL = "https://matthewa26.github.io/bouncer/"

    /// What the script analyzes.
    public let scope: XcodeScope

    /// Which findings fail the build.
    public let failOn: XcodeFailOn

    /// Creates a script description.
    ///
    /// - Parameters:
    ///   - scope: What the script analyzes.
    ///   - failOn: Which findings fail the build.
    public init(scope: XcodeScope, failOn: XcodeFailOn) {
        self.scope = scope
        self.failOn = failOn
    }

    /// The warning a build shows instead of running Bouncer under user script sandboxing, where it can't read
    /// the sources and would otherwise pass without checking anything.
    static let sandboxWarning = "Bouncer can't read your sources while User Script Sandboxing is on; run "
        + "'bouncer xcode install --disable-script-sandboxing' or set it to No in this target's Build Settings."

    /// The script's text.
    ///
    /// Xcode runs build phases with a minimal `PATH`, so the usual install locations are added first. A missing
    /// `bouncer`, or a sandbox it can't read through, only warns, so the build still succeeds.
    public var text: String {
        [
            Self.marker,
            "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH\"",
            "if ! command -v bouncer >/dev/null 2>&1; then",
            "  echo \"warning: Bouncer isn't installed; see \(Self.installURL)\"",
            "  exit 0",
            "fi",
            "if [ \"$ENABLE_USER_SCRIPT_SANDBOXING\" = YES ]; then",
            "  echo \"warning: \(Self.sandboxWarning)\"",
            "  exit 0",
            "fi",
            "cd \"$SRCROOT\" || exit 0",
            command
        ].joined(separator: "\n") + "\n"
    }

    /// The `bouncer` invocation, with how its result reaches Xcode.
    ///
    /// With `never`, Xcode would still fail a build whose script printed an `error:` line, so errors are
    /// rewritten as warnings and the script always succeeds.
    var command: String {
        let base = "bouncer \(arguments) --format xcode --progress off --no-update-check"
        switch failOn {
        case .error: return base + " --severity-threshold error"
        case .warning: return base + " --severity-threshold warning"
        case .never: return base + " | sed -E 's/^(.+:[0-9]+:[0-9]+): error: /\\1: warning: /'\nexit 0"
        }
    }

    /// The subcommand and its path argument for the scope. A review skips `.xcodeproj` bundles, whose
    /// generated `project.pbxproj` would otherwise fill the Issue navigator with long-line warnings.
    private var arguments: String {
        switch scope {
        case .check: return "check"
        case .review: return "review \"$SRCROOT\" --exclude '**/*.xcodeproj/**'"
        }
    }

    /// Whether a script was added by `bouncer xcode install`.
    ///
    /// - Parameter script: A Run Script phase's script text.
    /// - Returns: Whether it carries Bouncer's marker line.
    public static func isBouncerScript(_ script: String?) -> Bool {
        script?.contains("Added by 'bouncer xcode install'") ?? false
    }
}
