import Foundation

/// Tells the user where a written report is and how to open it, including the address a Windows browser or
/// tool needs when Bouncer runs inside WSL, where a Linux path or a `localhost` URL doesn't reach the file.
public enum ReportLink {
    /// Describes a written report file. Under WSL the `Open:` link is the Windows URL, since the terminal hands
    /// a clicked link to a Windows browser, which can't open a Linux `file:///home/…` URL.
    ///
    /// - Parameters:
    ///   - file: The report's absolute location.
    ///   - environment: The process environment; `WSL_DISTRO_NAME` marks a WSL session.
    /// - Returns: Lines naming the file and a URL to open it, and under WSL, the file's Windows path.
    public static func lines(for file: URL, environment: [String: String]) -> [String] {
        let written = "Report written to \(file.path)"
        guard let distro = environment["WSL_DISTRO_NAME"], !distro.isEmpty else {
            return [written, "Open: \(file.absoluteString)"]
        }
        let windows = windowsLocation(forLinuxPath: file.path, distro: distro)
        return [written, "Open: \(windows.url)", "Windows path: \(windows.path)"]
    }

    /// Maps a Linux path inside WSL to how Windows reaches it: a drive path for files under `/mnt/<drive>/`,
    /// otherwise the distribution's `\\wsl.localhost\<distro>\…` share.
    ///
    /// - Parameters:
    ///   - path: The absolute Linux path.
    ///   - distro: The WSL distribution's name.
    /// - Returns: The Windows path and its `file:` URL.
    public static func windowsLocation(forLinuxPath path: String, distro: String) -> (path: String, url: String) {
        let segments = path.split(separator: "/").map(String.init)
        if segments.count > 2, segments[0] == "mnt", segments[1].count == 1, segments[1].first?.isLetter == true {
            let drive = segments[1].uppercased() + ":"
            let rest = Array(segments.dropFirst(2))
            return (([drive] + rest).joined(separator: "\\"), "file:///\(drive)/" + encoded(rest))
        }
        let share = ["", "", "wsl.localhost", distro] + segments
        return (share.joined(separator: "\\"), "file://wsl.localhost/" + encoded([distro] + segments))
    }

    /// Percent-encodes path segments and joins them with `/`.
    ///
    /// - Parameter segments: The segments.
    /// - Returns: The encoded path.
    private static func encoded(_ segments: [String]) -> String {
        segments.map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }.joined(separator: "/")
    }
}
