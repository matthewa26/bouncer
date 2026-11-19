import SwiftSyntax
import SwiftParser
import BouncerCore

/// A Swift file parsed once, with its line converter, shared by the rules and the module-facts extractor.
struct Parsed {
    let file: SourceFile
    let tree: SourceFileSyntax
    let converter: SourceLocationConverter

    /// Parses a file.
    ///
    /// - Parameter file: The Swift file.
    init(_ file: SourceFile) {
        self.file = file
        tree = Parser.parse(source: file.contents)
        converter = SourceLocationConverter(fileName: file.path.path, tree: tree)
    }
}

/// Reads a Swift file's module facts: its imports by module name, its public declarations, and every
/// name it refers to.
enum SwiftModuleFacts {
    /// Extracts module facts from a parsed file.
    ///
    /// - Parameter parsed: The parsed file.
    /// - Returns: Its imports, public declarations, and referenced names.
    static func facts(of parsed: Parsed) -> ModuleFacts {
        let api = SwiftPublicAPICollector(converter: parsed.converter)
        api.walk(parsed.tree)
        let references = SwiftReferenceCollector(viewMode: .sourceAccurate)
        references.walk(parsed.tree)
        return ModuleFacts(imports: imports(of: parsed), exports: api.exports, references: references.names.sorted())
    }

    /// Reads a file's imports by module name.
    ///
    /// - Parameter parsed: The parsed file.
    /// - Returns: Its imports.
    private static func imports(of parsed: Parsed) -> [ImportFact] {
        let declarations = parsed.tree.statements.compactMap { $0.item.as(ImportDeclSyntax.self) }
        let imports = declarations.compactMap { node -> ImportFact? in
            guard let module = node.path.first?.name.text else { return nil }
            let line = parsed.converter.location(for: node.positionAfterSkippingLeadingTrivia).line
            return ImportFact(specifier: module, line: line)
        }
        return imports
    }
}
