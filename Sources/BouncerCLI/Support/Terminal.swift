import Foundation
#if os(Windows)
import ucrt
#endif

/// Detects whether the standard streams are attached to an interactive terminal, on every platform.
///
/// `FileHandle.fileDescriptor` is unavailable on Windows, so this checks the standard descriptors
/// directly, with the C runtime's `_isatty` on Windows and POSIX `isatty` elsewhere.
enum Terminal {
    /// Whether standard input is a terminal, so a human could answer a prompt.
    static var standardInputIsInteractive: Bool { isTerminal(0) }

    /// Whether standard output is a terminal, so a human is likely reading it.
    static var standardOutputIsInteractive: Bool { isTerminal(1) }

    /// Checks one file descriptor.
    ///
    /// - Parameter descriptor: The descriptor, such as 0 for standard input.
    /// - Returns: Whether it refers to a terminal.
    private static func isTerminal(_ descriptor: Int32) -> Bool {
        #if os(Windows)
        return _isatty(descriptor) != 0
        #else
        return isatty(descriptor) != 0
        #endif
    }
}
