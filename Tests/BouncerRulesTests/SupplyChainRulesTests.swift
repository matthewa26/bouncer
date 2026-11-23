import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class SupplyChainRulesTests: XCTestCase {
    private let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])

    private func file(_ path: String, _ contents: String) -> SourceFile {
        let url = URL(fileURLWithPath: "/repo/" + path)
        return SourceFile(path: url, language: Language.from(fileExtension: url.pathExtension), contents: contents)
    }

    private func lines(_ rule: Rule, _ path: String, _ contents: String, context: AnalysisContext? = nil) -> [Int] {
        rule.evaluate(file: file(path, contents), context: context ?? self.context).map(\.line)
    }

    // MARK: pipe-to-shell

    func testFlagsDownloadsPipedIntoAShellAcrossFileKinds() {
        let script = """
            #!/bin/sh
            curl -fsSL https://get.example.org/install | sh
            wget -qO- https://x.org/i | sudo -E bash -
            curl -sSL get.docker.com | sudo sh
            bash <(curl -s https://x.org/a)
            sh -c "$(curl -fsSL https://x.org/omz)"
            curl https://x.org/a.py | python3
            """
        XCTAssertEqual(lines(PipeToShellRule(), "install.sh", script), [2, 3, 4, 5, 6, 7])
        XCTAssertEqual(lines(PipeToShellRule(), "Dockerfile", "RUN curl -fsSL https://x.org/s | bash\n"), [1])
        XCTAssertEqual(lines(PipeToShellRule(), "Makefile", "setup:\n\tcurl https://x.org/s | sh\n"), [2])
        XCTAssertEqual(lines(PipeToShellRule(), "ci.yml", "    - run: curl -sSL https://x.org/i | bash\n"), [1])
        XCTAssertEqual(lines(PipeToShellRule(), "tool", "#!/usr/bin/env bash\ncurl https://x.org | bash\n"), [2])
    }

    func testFlagsPowerShellDownloadsRunWithInvokeExpression() {
        let script = """
            irm https://x.org/install.ps1 | iex
            Invoke-WebRequest -Uri $url | Invoke-Expression
            iex ((New-Object System.Net.WebClient).DownloadString('https://x.org/i.ps1'))
            Get-Content -Raw install.ps1 | Invoke-Expression
            """
        XCTAssertEqual(lines(PipeToShellRule(), "setup.ps1", script), [1, 2, 3])
    }

    func testIgnoresVerifiedDownloadsCommentsPlaceholdersMarkdownAndOtherPipes() {
        let script = """
            curl -fsSL -o install.sh https://x.org/install.sh && sha256sum -c install.sh.sha256 && sh install.sh
            # curl -fsSL https://x.org/install | sh
            echo 'run: curl -fsSL <url> | sh'
            curl -fsSL https://x.org/a.tgz | tar xz
            curl https://x.org/sum | shasum -a 256
            curl https://x.org || sh fallback.sh
            """
        XCTAssertEqual(lines(PipeToShellRule(), "install.sh", script), [])
        XCTAssertEqual(lines(PipeToShellRule(), "README.md", "curl -fsSL https://x.org/i | sh\n"), [])
        XCTAssertEqual(lines(PipeToShellRule(), "main.py", "os.system('curl https://x.org | sh')\n"), [])
    }

    // MARK: unpinned-ci-action

    private let workflow = """
        jobs:
          build:
            steps:
              - uses: actions/checkout@v4
              - uses: actions/setup-node@0123456789abcdef0123456789abcdef01234567 # v4.0.2
              - uses: ./.github/actions/local
              - uses: docker://alpine@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
              - uses: docker://alpine:3
              - uses: "owner/repo/path@main"
        """

    private var enabled: AnalysisContext {
        let settings = RuleSettings(enabled: true, severity: .info, parameters: .empty)
        return AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: ["unpinned-ci-action": settings])
    }

    func testCIActionPinsAreOffUnlessConfigured() {
        XCTAssertEqual(lines(UnpinnedCIActionRule(), ".github/workflows/ci.yml", workflow), [])
    }

    func testFlagsTagsBranchesAndUndigestedImagesButNotShasOrLocalActions() {
        XCTAssertEqual(lines(UnpinnedCIActionRule(), ".github/workflows/ci.yml", workflow, context: enabled), [4, 8, 9])
        XCTAssertEqual(lines(UnpinnedCIActionRule(), "action.yml", "runs:\n  steps:\n    - uses: a/b@v1\n",
                             context: enabled), [3])
        XCTAssertEqual(lines(UnpinnedCIActionRule(), "deploy/config.yml", workflow, context: enabled), [])
    }

    func testCIActionSeverityComesFromItsSettings() {
        let found = UnpinnedCIActionRule().evaluate(file: file(".github/workflows/ci.yml", workflow), context: enabled)
        XCTAssertEqual(Set(found.map(\.severity)), [.info])
    }

    // MARK: unpinned-dependency

    func testFlagsUnpinnedNpmDependenciesAtTheirLines() {
        let manifest = """
            {
              "name": "web",
              "dependencies": {
                "any": "*",
                "caret": "^1.2.3",
                "tag": "latest",
                "branch": "github:o/r#main",
                "commit": "git+https://github.com/o/r.git#0123456789abcdef0123456789abcdef01234567",
                "short": "o/r",
                "open": ">=2",
                "bounded": ">=2 <3",
                "tarball": "https://x.org/t.tgz",
                "local": "file:../local",
                "alias": "npm:other@*"
              },
              "devDependencies": { "x": "" },
              "peerDependencies": { "react": "*" }
            }
            """
        XCTAssertEqual(lines(UnpinnedDependencyRule(), "package.json", manifest).sorted(), [4, 6, 7, 9, 10, 12, 14, 16])
    }

    func testFlagsCargoStarsAndGitSourcesWithoutARev() {
        let manifest = """
            [package]
            name = "app"
            version = "0.1.0"

            [dependencies]
            serde = "*" # anything
            tokio = { version = "1", features = ["full"] }
            branch = { git = "https://github.com/o/b", branch = "main" }
            head = { git = "https://github.com/o/h" }
            tagged = { git = "https://github.com/o/t", tag = "v1.0" }
            pinned = { git = "https://github.com/o/p", rev = "0123abc" }
            shared = { workspace = true }

            [target.'cfg(unix)'.dev-dependencies]
            nix = "*"

            [workspace.dependencies.own]
            git = "https://github.com/o/own"
            branch = "dev"

            [features]
            default = []
            """
        XCTAssertEqual(lines(UnpinnedDependencyRule(), "Cargo.toml", manifest), [6, 8, 9, 15, 17])
    }

    func testFlagsComposerStarsBranchesAndOpenRangesButNotPlatformRequirements() {
        let manifest = """
            {
              "require": {
                "php": ">=8.4",
                "ext-json": "*",
                "any/thing": "*",
                "caret/pkg": "^1.2",
                "tilde/pkg": "~1.2",
                "exact/pkg": "1.2.3",
                "either/pkg": "^4.5 || ^5.0",
                "open/pkg": ">=1.0",
                "bounded/pkg": ">=1.0 <2.0",
                "master/pkg": "dev-master",
                "alias/pkg": "0.2.x-dev",
                "pinned/pkg": "dev-main#0123abc",
                "inline/pkg": "dev-main as 1.0.x-dev",
                "beta/pkg": "^1.2@beta"
              },
              "require-dev": { "main/pkg": "dev-main", "star/dev": "*@dev" }
            }
            """
        let found = UnpinnedDependencyRule().evaluate(file: file("composer.json", manifest), context: context)
        XCTAssertEqual(found.map(\.line).sorted(), [5, 10, 12, 13, 15, 18, 18])
        XCTAssertTrue(found.contains { $0.message.contains("\"alias/pkg\" is \"0.2.x-dev\", which follows a development") })
        XCTAssertEqual(lines(UnpinnedDependencyRule(), "composer.json", "not json"), [])
    }

    func testFlagsSwiftPackagesFollowingABranch() {
        let manifest = """
            let package = Package(
                dependencies: [
                    .package(url: "https://github.com/a/b.git", branch: "main"),
                    .package(url: "https://github.com/a/c.git", from: "1.0.0"),
                    .package(url: "https://github.com/a/d.git", revision: "abc123"),
                    // .package(url: "https://github.com/a/e.git", branch: "main"),
                    .package(
                        url: "https://github.com/a/f.git",
                        branch: "dev"
                    ),
                    .package(url: "https://github.com/a/g.git", .branch("old")),
                ]
            )
            """
        let found = UnpinnedDependencyRule().evaluate(file: file("Package.swift", manifest), context: context)
        XCTAssertEqual(found.map(\.line), [3, 7, 11])
        XCTAssertTrue(found[1].message.contains("https://github.com/a/f.git"))
    }

    func testIgnoresFilesThatAreNotManifests() {
        XCTAssertEqual(lines(UnpinnedDependencyRule(), "config.json", "{\"dependencies\": {\"a\": \"*\"}}"), [])
    }
}
