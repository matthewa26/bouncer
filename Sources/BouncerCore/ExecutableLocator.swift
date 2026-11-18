import Foundation

/// Finds a command-line tool on `PATH`, the way a shell would, on every platform.
///
/// Hard-coding a location such as `/usr/bin/git` breaks on Windows and misses tools installed
/// elsewhere, such as Homebrew's. On Windows the search uses `;` separators and tries each
/// `PATHEXT` extension, so `git` finds `git.exe`.
public enum ExecutableLocator {
    /// Looks up a tool by name.
    ///
    /// - Parameters:
    ///   - name: The tool's name without an extension, such as `git`.
    ///   - environment: The environment whose `PATH` (and, on Windows, `PATHEXT`) to search.
    /// - Returns: The first matching executable's path, or `nil` if it isn't on `PATH`.
    public static func path(
        of name: String, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let candidates = searchDirectories(environment).flatMap { directory in
            fileNames(for: name, environment).map { URL(fileURLWithPath: directory).appendingPathComponent($0).path }
        }
        return candidates.first(where: isExecutableFile)
    }

    /// Reports whether a path is an existing, executable file.
    ///
    /// Windows Foundation's `isExecutableFile` returns true even for paths that don't exist, so this
    /// requires the file to exist first; on Windows, a file with a `PATHEXT` extension is executable.
    ///
    /// - Parameter path: The candidate path.
    /// - Returns: Whether it can be launched.
    private static func isExecutableFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        #if os(Windows)
        return true
        #else
        return FileManager.default.isExecutableFile(atPath: path)
        #endif
    }

    /// Splits `PATH` into directories.
    ///
    /// - Parameter environment: The environment to read `PATH` from (`Path` on Windows).
    /// - Returns: The directories to search, in order.
    private static func searchDirectories(_ environment: [String: String]) -> [String] {
        #if os(Windows)
        let path = environment.first { $0.key.uppercased() == "PATH" }?.value ?? ""
        return path.split(separator: ";").map(String.init)
        #else
        return (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        #endif
    }

    /// Lists the file names a tool may have: just the name, or on Windows the name plus each `PATHEXT` extension.
    ///
    /// - Parameters:
    ///   - name: The tool's name.
    ///   - environment: The environment to read `PATHEXT` from.
    /// - Returns: The file names to try, in order.
    private static func fileNames(for name: String, _ environment: [String: String]) -> [String] {
        #if os(Windows)
        let extensions = (environment["PATHEXT"] ?? ".COM;.EXE;.BAT;.CMD").split(separator: ";")
        return extensions.map { name + $0.lowercased() }
        #else
        return [name]
        #endif
    }
}
