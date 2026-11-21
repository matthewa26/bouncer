import Foundation
import SwiftTreeSitter
import BouncerCore

/// Rust's own smells, found in one walk of a file's tree.
///
/// - `rust-unwrap`: `.unwrap()` or `.expect(…)` outside test code.
/// - `rust-unsafe-without-safety-comment`: an `unsafe` block, `unsafe fn`, or `unsafe impl` with no `// SAFETY:`
///   comment (or, above an `unsafe fn`, a `# Safety` doc section) directly above it or opening the block. A trait's
///   or trait impl's `unsafe fn`s share the trait's documented contract, so they aren't checked.
/// - `rust-todo-macro`: `todo!()` or `unimplemented!()`, anywhere.
/// - `rust-debug-print`: `dbg!` anywhere, and `println!`, `print!`, `eprintln!`, or `eprint!` outside tests and
///   programs (see `RustCrateLayout.isProgram`, or a file declaring `fn main`), since a command-line tool prints on
///   purpose but a library shouldn't.
/// - `rust-panic`: `panic!` outside tests and programs.
/// - `rust-shell-injection`: `Command::new("sh")` (or `bash`, `zsh`, `cmd`, `powershell`) given `-c` or `/C` and an
///   argument built with `format!` or `+` in the same statement. A command built into a variable first isn't
///   followed.
///
/// Test code is a function with a `#[test]`-style attribute, an item under `#[cfg(test)]`, a file starting with
/// `#![cfg(test)]`, or a file that's test code by its path (see `RustCrateLayout.isTestFile`). Macros nested in
/// another macro's arguments (`vec![x.unwrap()]`) aren't parsed, so they aren't checked.
struct RustSmells: LanguageSmellExtractor {
    /// Lists a Rust file's smells.
    ///
    /// - Parameter tree: The parsed file.
    /// - Returns: One finding per smell whose rule is enabled.
    func findings(in tree: SmellTree) -> [Finding] {
        let walk = RustSmellWalk(tree: tree)
        walk.walk(tree.root, in: walk.layout.isTestFile ? .test : .code)
        return walk.findings
    }
}

/// Whether a node is test code, where crashing on a bad value and printing are fine.
enum RustCodeKind {
    case code
    case test
}

/// One walk of a Rust file, collecting its smells.
final class RustSmellWalk {
    private static let testAttribute = #"^#\[\s*((\w+::)*test|rstest|test_case|quickcheck)\b"#
    private static let cfgTest = #"^#!?\[\s*cfg\s*\((?![^\]]*not\s*\(\s*test)[^\]]*\btest\b"#
    private static let safetyComment = #"(?i)\bsafety\s*:|#\s*safety\b"#
    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "cmd", "cmd.exe", "powershell", "pwsh"]
    private static let shellFlag = #"\.args?\s*\(\s*(&?\[)?\s*"(-c|/C|/c|-Command)""#
    private static let builtArgument = #"format!\s*\(|[\w)"]\s*\+\s*[\w"&(]"#
    private static let printMacros: Set<String> = ["println", "print", "eprintln", "eprint"]
    private static let statementParents: Set<String> = ["block", "source_file", "declaration_list"]
    private static let unsafeBlock = "unsafe_block"
    /// What each kind of unsafe node is called in a finding.
    private static let unsafeNames = [
        unsafeBlock: "unsafe block", "impl_item": "unsafe impl", "function_item": "unsafe fn"
    ]

    private let tree: SmellTree
    let layout: RustCrateLayout
    /// Whether the file is part of a program: by its place in the package, or by declaring `fn main` itself.
    private let isProgram: Bool
    private(set) var findings: [Finding] = []

    /// Starts a walk over one file.
    ///
    /// - Parameter tree: The parsed file.
    init(tree: SmellTree) {
        self.tree = tree
        layout = RustCrateLayout(file: tree.file.path, repoRoot: tree.context.repoRoot)
        isProgram = layout.isProgram || TreeWalk.namedChildren(tree.root).contains {
            $0.nodeType == "function_item" && $0.child(byFieldName: "name").flatMap(tree.text) == "main"
        }
    }

    /// Checks a node, then its children, tracking whether they're test code.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - kind: Whether the code around the node is test code.
    func walk(_ node: Node, in kind: RustCodeKind) {
        let own = isTestItem(node) ? RustCodeKind.test : kind
        check(node, kind: own)
        for child in TreeWalk.namedChildren(node) { walk(child, in: own) }
    }

    /// Reports whether an item is test code by its own attributes: a test function or a `#[cfg(test)]` item, or a
    /// file opening with `#![cfg(test)]`.
    ///
    /// - Parameter node: The item, or the file's root.
    /// - Returns: Whether it's test code.
    func isTestItem(_ node: Node) -> Bool {
        if node.nodeType == "source_file" {
            return TreeWalk.namedChildren(node).contains {
                $0.nodeType == "inner_attribute_item" && matches(Self.cfgTest, $0)
            }
        }
        let attributes = RustSyntax.preamble(of: node).filter { $0.nodeType == "attribute_item" }
        return attributes.contains { matches(Self.cfgTest, $0) || matches(Self.testAttribute, $0) }
    }

    /// Checks one node for each smell its type can have.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - kind: Whether it's test code.
    private func check(_ node: Node, kind: RustCodeKind) {
        let type = node.nodeType ?? ""
        if type == "call_expression" {
            if kind == .code { checkUnwrap(node) }
            checkShellCommand(node)
        } else if type == "macro_invocation" {
            checkMacro(node, kind: kind)
        } else if Self.unsafeNames[type] != nil {
            checkUnsafe(node)
        }
    }

    /// Flags `.unwrap()` and `.expect(…)`.
    ///
    /// - Parameter call: A call expression.
    private func checkUnwrap(_ call: Node) {
        guard let callee = call.child(byFieldName: "function"), callee.nodeType == "field_expression",
              let method = callee.child(byFieldName: "field"), let name = tree.text(of: method),
              let arguments = call.child(byFieldName: "arguments") else { return }
        let count = TreeWalk.namedChildren(arguments).filter { !RustSyntax.isComment($0) }.count
        guard (name == "unwrap" && count == 0) || (name == "expect" && count == 1) else { return }
        report("rust-unwrap", at: method, "." + name + "() panics on None or Err; handle it or propagate it with ?.")
    }

    /// Flags a debug, unfinished-code, or panicking macro.
    ///
    /// - Parameters:
    ///   - node: A macro invocation.
    ///   - kind: Whether it's test code.
    private func checkMacro(_ node: Node, kind: RustCodeKind) {
        guard let name = macroName(node) else { return }
        let isLibrary = kind == .code && !isProgram
        if name == "todo" || name == "unimplemented" {
            report("rust-todo-macro", at: node, name + "!() panics when reached; finish the code before committing.")
        } else if name == "dbg" || (Self.printMacros.contains(name) && isLibrary) {
            report("rust-debug-print", at: node, "Remove " + name + "! debug output, or use a logging crate.")
        } else if name == "panic", isLibrary {
            report("rust-panic", at: node, "panic! in library code crashes the caller; return an error instead.")
        }
    }

    /// Names a macro without its path, as `println` for `std::println!`.
    ///
    /// - Parameter node: A macro invocation.
    /// - Returns: The macro's name.
    private func macroName(_ node: Node) -> String? {
        guard let macro = node.child(byFieldName: "macro") else { return nil }
        return tree.text(of: macro.child(byFieldName: "name") ?? macro)
    }

    /// Flags an `unsafe` block, function, or impl that no safety comment explains.
    ///
    /// - Parameter node: An unsafe block, or a function or impl to check for the `unsafe` keyword.
    private func checkUnsafe(_ node: Node) {
        guard node.nodeType == Self.unsafeBlock || isUnsafeItem(node), !hasSafetyComment(node),
              let what = Self.unsafeNames[node.nodeType ?? ""] else { return }
        report("rust-unsafe-without-safety-comment", at: node,
               "This " + what + " has no // SAFETY: comment saying why its invariants hold.")
    }

    /// Reports whether a function or impl is declared `unsafe` and owns its safety contract. A trait's methods and
    /// a trait impl's methods share the contract the trait documents, so they aren't checked one by one.
    ///
    /// - Parameter node: A function or impl item.
    /// - Returns: Whether its modifiers include `unsafe`, outside a trait or trait impl.
    private func isUnsafeItem(_ node: Node) -> Bool {
        if let owner = node.parent?.parent, owner.nodeType == "trait_item"
            || (owner.nodeType == "impl_item" && owner.child(byFieldName: "trait") != nil) { return false }
        return (0..<node.childCount).compactMap(node.child(at:)).contains { child in
            child.nodeType == "unsafe" || (child.nodeType == "function_modifiers"
                && (tree.text(of: child) ?? "").split(separator: " ").contains("unsafe"))
        }
    }

    /// Reports whether a safety comment explains an unsafe node: one opening the block, one directly above the
    /// node or any expression around it up to its statement, one on the lines right above its first line (inside a
    /// method chain, say), or one trailing that statement on its last line.
    ///
    /// - Parameter node: The unsafe block or item.
    /// - Returns: Whether such a comment exists.
    private func hasSafetyComment(_ node: Node) -> Bool {
        let lines = commentLines(above: Int(node.pointRange.lowerBound.row))
        return lines.contains { $0.range(of: Self.safetyComment, options: .regularExpression) != nil }
            || commentNodes(explaining: node).contains { matches(Self.safetyComment, $0) }
    }

    /// Lists the comments in the tree that could explain an unsafe node.
    ///
    /// - Parameter node: The unsafe block or item.
    /// - Returns: The block's opening comment, the comments above it and the expressions around it up to its
    ///   statement, and a comment trailing that statement on its last line.
    private func commentNodes(explaining node: Node) -> [Node] {
        let opening = node.nodeType == Self.unsafeBlock ? node.namedChild(at: 0)?.namedChild(at: 0) : nil
        let enclosing = enclosingNodes(upToStatement: node)
        let trailing = enclosing.last?.nextNamedSibling.flatMap { sibling in
            sibling.pointRange.lowerBound.row == enclosing.last?.pointRange.upperBound.row ? sibling : nil
        }
        let candidates = [opening, trailing].compactMap { $0 } + enclosing.flatMap(RustSyntax.preamble(of:))
        return candidates.filter(RustSyntax.isComment)
    }

    /// Lists the run of `//` comment lines directly above a line, nearest first.
    ///
    /// - Parameter row: The 0-indexed line.
    /// - Returns: The comment lines, stopping at the first line that isn't one.
    private func commentLines(above row: Int) -> [Substring] {
        let lines = tree.file.lines
        let above = lines[..<min(max(row, 0), lines.count)].reversed().lazy.map { $0.drop { $0 == " " || $0 == "\t" } }
        return Array(above.prefix { $0.hasPrefix("//") })
    }

    /// Lists a node and the expressions around it, up to the statement or item that holds it.
    ///
    /// - Parameter node: The node.
    /// - Returns: The node first, then each parent, ending with the statement.
    private func enclosingNodes(upToStatement node: Node) -> [Node] {
        var nodes = [node], current = node
        while let parent = current.parent, !Self.statementParents.contains(parent.nodeType ?? "") {
            nodes.append(parent)
            current = parent
        }
        return nodes
    }

    /// Flags `Command::new("sh")` run with `-c` and a command built by `format!` or concatenation.
    ///
    /// - Parameter call: A call expression.
    private func checkShellCommand(_ call: Node) {
        guard startsShell(call), let statement = enclosingNodes(upToStatement: call).last.flatMap(tree.text),
              let start = tree.text(of: call).flatMap({ statement.range(of: $0) }),
              Self.passesBuiltCommand(statement[start.lowerBound...]) else { return }
        report("rust-shell-injection", at: call,
               "Shell command built with format! or + risks injection; run the program directly with .arg().")
    }

    /// Reports whether a call is `Command::new` with a shell as its program.
    ///
    /// - Parameter call: A call expression.
    /// - Returns: Whether it starts a shell such as `sh` or `/bin/bash`.
    private func startsShell(_ call: Node) -> Bool {
        guard let callee = call.child(byFieldName: "function").flatMap(tree.text), callee.hasSuffix("Command::new"),
              let program = call.child(byFieldName: "arguments")?.namedChild(at: 0),
              program.nodeType == "string_literal", let name = tree.text(of: program).map(TreeWalk.unquote)
        else { return false }
        return Self.shells.contains((name as NSString).lastPathComponent)
    }

    /// Reports whether a command chain passes the shell `-c` and then a command built by `format!` or `+`.
    ///
    /// - Parameter chain: The statement's text from `Command::new` on.
    /// - Returns: Whether a built command follows the flag.
    private static func passesBuiltCommand(_ chain: Substring) -> Bool {
        guard let flag = chain.range(of: shellFlag, options: .regularExpression) else { return false }
        return chain[flag.upperBound...].range(of: builtArgument, options: .regularExpression) != nil
    }

    /// Reports whether a node's text matches a pattern.
    ///
    /// - Parameters:
    ///   - pattern: The regular expression.
    ///   - node: The node.
    /// - Returns: Whether it matches.
    private func matches(_ pattern: String, _ node: Node) -> Bool {
        tree.text(of: node)?.range(of: pattern, options: .regularExpression) != nil
    }

    /// Records a finding, if its rule is enabled.
    ///
    /// - Parameters:
    ///   - ruleID: The rule.
    ///   - node: Where it's found.
    ///   - message: What's wrong.
    private func report(_ ruleID: String, at node: Node, _ message: String) {
        if let finding = tree.finding(ruleID, at: node, message) { findings.append(finding) }
    }
}
