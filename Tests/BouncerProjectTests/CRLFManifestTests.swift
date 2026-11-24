import XCTest
import Foundation
import BouncerCore
@testable import BouncerProject

final class CRLFManifestTests: XCTestCase {
    func testReadsACRLFGoModLineByLine() {
        let module = GoModule(path: "go.mod", text: "module example.com/app\r\n\r\nrequire (\r\n\tgithub.com/a/b v1.0.0\r\n)\r\n")
        XCTAssertEqual(module.module, "example.com/app")
        XCTAssertEqual(module.requirements, [DeclaredDependency(name: "github.com/a/b", line: 4)])
    }

    func testNumbersCRLFManifestLinesLikeLFOnes() {
        let code = "// a\r\n/* b\r\n c */\r\nlet x = 1\r\n"
        let stripped = ManifestText.stripComments(code)
        XCTAssertEqual(ManifestText.line(of: stripped.range(of: "let")!.lowerBound, in: stripped), 4)
    }
}
