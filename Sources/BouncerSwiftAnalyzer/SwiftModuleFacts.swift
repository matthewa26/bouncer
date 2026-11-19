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
    /// - Returns: Its imports, public declarations, referenced names, and structure.
    static func facts(of parsed: Parsed) -> ModuleFacts {
        let api = SwiftPublicAPICollector(converter: parsed.converter)
        let references = SwiftReferenceCollector(viewMode: .sourceAccurate)
        let structure = SwiftStructureCollector(parsed)
        for visitor in [api, references, structure] as [SyntaxVisitor] { visitor.walk(parsed.tree) }
        let names = references.names.sorted()
        return ModuleFacts(
            imports: imports(of: parsed), exports: api.exports, references: names, structure: structure.structure
        )
    }

    /// Reads a file's imports by module name, including those inside `#if` blocks.
    ///
    /// - Parameter parsed: The parsed file.
    /// - Returns: Its imports.
    private static func imports(of parsed: Parsed) -> [ImportFact] {
        let declarations = importDeclarations(in: parsed.tree.statements)
        let imports = declarations.compactMap { node -> ImportFact? in
            guard let module = node.path.first?.name.text else { return nil }
            let line = parsed.converter.location(for: node.positionAfterSkippingLeadingTrivia).line
            return ImportFact(specifier: module, line: line)
        }
        return imports
    }

    /// Lists the import declarations among file-level statements, descending into `#if` clauses.
    ///
    /// - Parameter statements: The statements.
    /// - Returns: The imports, in source order.
    private static func importDeclarations(in statements: CodeBlockItemListSyntax) -> [ImportDeclSyntax] {
        statements.flatMap { statement -> [ImportDeclSyntax] in
            if let declaration = statement.item.as(ImportDeclSyntax.self) { return [declaration] }
            let clauses = statement.item.as(IfConfigDeclSyntax.self)?.clauses ?? []
            return clauses.flatMap { clause in
                clause.elements?.as(CodeBlockItemListSyntax.self).map(importDeclarations) ?? []
            }
        }
    }
}
