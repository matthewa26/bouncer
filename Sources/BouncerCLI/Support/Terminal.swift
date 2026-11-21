import Foundation
#if os(Windows)
import ucrt
import WinSDK
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

    /// Whether standard error is a terminal, so a redrawn progress line will render.
    static var standardErrorIsInteractive: Bool { isTerminal(2) }

    /// The width of the terminal standard error is attached to: `COLUMNS` when set, otherwise the terminal's
    /// own size where it can be read, otherwise 80.
    static var standardErrorColumns: Int {
        if let columns = ProcessInfo.processInfo.environment["COLUMNS"].flatMap(Int.init), columns > 0 {
            return columns
        }
        return windowColumns(2) ?? defaultColumns
    }

    /// The width assumed when the terminal's own can't be read.
    private static let defaultColumns = 80

    /// Turns on ANSI escape handling for standard error, which a Windows console needs before a live line
    /// can redraw itself; other platforms always have it.
    ///
    /// - Returns: Whether escape sequences will be honored.
    static func enableVirtualTerminalOnStandardError() -> Bool {
        #if os(Windows)
        let invalid = HANDLE(bitPattern: -1)
        guard let handle = GetStdHandle(STD_ERROR_HANDLE), handle != invalid else { return false }
        var mode: DWORD = 0
        guard GetConsoleMode(handle, &mode) else { return false }
        return SetConsoleMode(handle, mode | DWORD(ENABLE_VIRTUAL_TERMINAL_PROCESSING))
        #else
        return true
        #endif
    }

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

    /// Asks the terminal on a descriptor for its width, where the platform makes that easy.
    ///
    /// - Parameter descriptor: The descriptor.
    /// - Returns: The width in columns, or `nil` when it can't be read.
    private static func windowColumns(_ descriptor: Int32) -> Int? {
        #if canImport(Darwin)
        var size = winsize()
        guard ioctl(descriptor, TIOCGWINSZ, &size) == 0, size.ws_col > 0 else { return nil }
        return Int(size.ws_col)
        #else
        return nil
        #endif
    }
}
