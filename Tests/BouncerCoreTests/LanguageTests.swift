import XCTest
@testable import BouncerCore

final class LanguageTests: XCTestCase {
    func testMapsObjectiveCAndObjectiveCPlusPlusExtensions() {
        XCTAssertEqual(Language.from(fileExtension: "m"), .objc)
        XCTAssertEqual(Language.from(fileExtension: "MM"), .objc)
        XCTAssertEqual(Language.from(fileExtension: "h"), .c)
    }

    func testSniffsObjectiveCHeadersByTheirDirectives() {
        let markers = [
            "@interface Foo : NSObject\n@end\n", "@protocol Doer\n@end\n", "@class Foo;\n", "@import Foundation;\n",
            "#import <Foundation/Foundation.h>\n", "NS_ASSUME_NONNULL_BEGIN\nNS_ASSUME_NONNULL_END\n",
            "  @property (nonatomic) int count;\n"
        ]
        for header in markers {
            XCTAssertEqual(Language.from(fileExtension: "h", contents: header), .objc, header)
        }
    }

    func testKeepsPlainCHeadersAsC() {
        let header = "#ifndef FOO_H\n#define FOO_H\n#include <stdio.h>\n// @interface in a comment\nint foo(void);\n#endif\n"
        XCTAssertEqual(Language.from(fileExtension: "h", contents: header), .c)
    }

    func testOnlySniffsHeaders() {
        XCTAssertEqual(Language.from(fileExtension: "c", contents: "#import <x.h>\n"), .c)
        XCTAssertEqual(Language.from(fileExtension: "swift", contents: "@interface\n"), .swift)
    }
}
