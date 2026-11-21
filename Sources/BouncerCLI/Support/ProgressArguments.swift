import ArgumentParser
import BouncerReporting

/// The `--progress` and `--verbose` options `check`, `review`, and `baseline update` share.
struct ProgressArguments: ParsableArguments {
    @Option(help: "auto, live, plain, or off. Progress goes to stderr; auto is off for agent invocations.")
    var progress: ProgressMode = .auto

    @Flag(name: [.customLong("verbose"), .customShort("v")], help: "Log every step and file to stderr.")
    var verbose = false
}
