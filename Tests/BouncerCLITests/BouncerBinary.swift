import Foundation

/// Finds the `bouncer` executable that `swift test` built next to the test bundle.
enum BouncerBinary {
    /// The executable's file name on this platform.
    static var fileName: String {
        #if os(Windows)
        return "bouncer.exe"
        #else
        return "bouncer"
        #endif
    }

    /// The build products directory: the folder holding the `.xctest` bundle on macOS, or the test runner on Linux and
    /// Windows, where the bundle is itself an executable.
    static var productsDirectory: URL {
        #if os(macOS)
        if let bundle = Bundle.allBundles.first(where: { $0.bundlePath.hasSuffix(".xctest") }) {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        #endif
        return Bundle.main.bundleURL
    }

    /// Locates the built executable.
    ///
    /// - Returns: Its URL.
    /// - Throws: `EndToEndFailure` naming the path it looked at when there's no executable there.
    static func url() throws -> URL {
        let url = productsDirectory.appendingPathComponent(fileName)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw EndToEndFailure("no bouncer executable at \(url.path); build it with `swift build` first")
        }
        return url
    }
}
