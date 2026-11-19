import Foundation
import BouncerCore

/// Design-smell rules over a type's `TypeDesign` and a function's typed parameters: CBO, RFC, the
/// Lanza–Marinescu god-class formula, feature envy, temporary field, command–query separation, and
/// primitive obsession. Without type information each is a syntactic approximation, described per rule.
extension DeclarationFindings {
    /// Runs every design-smell rule except `god-class`'s formula, which `godClass` runs; test files, whose
    /// code reads results and builds fixtures by design, are skipped.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including each rule's resolved settings.
    /// - Returns: The combined findings.
    static func designSmellFindings(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        guard !TextMatching.isTestPath(file.path) else { return [] }
        return couplingBetweenObjects(summary, file: file, context: context)
            + responseForClass(summary, file: file, context: context)
            + featureEnvy(summary, file: file, context: context)
            + temporaryFields(summary, file: file, context: context)
            + commandQuerySeparation(summary, file: file, context: context)
            + primitiveObsession(summary, file: file, context: context)
    }

    /// Lists the types with measured design facts, alongside them, leaving out test suites.
    ///
    /// - Parameter summary: The declarations collected from the file's syntax tree.
    /// - Returns: Each measured type and its design facts.
    static func designedTypes(_ summary: DeclarationSummary) -> [(CollectedType, TypeDesign)] {
        summary.types.compactMap { type in type.design.map { (type, $0) } }.filter { !isTestTypeName($0.0.name) }
    }

    /// Flags every type that names more than `max` other types (CBO, Chidamber and Kemerer), counting
    /// the distinct type names in its annotations, constructor calls, and static member access, minus
    /// its own name, its nested types, its generic parameters, and the language's built-in types; off
    /// unless configured.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per over-coupled type.
    private static func couplingBetweenObjects(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        typeFindings("coupling-between-objects", summary, file: file, context: context) { type, design, parameters in
            let limit = parameters.int("max", default: 10)
            let coupled = design.referencedTypes.filter { !DesignVocabulary.isLibraryType($0, in: file.language) }
            guard coupled.count > limit else { return nil }
            return "Type \"\(type.name)\" is coupled to \(coupled.count) other types (CBO), over the \(limit) limit."
        }
    }

    /// Flags every type whose response set is over `max` (RFC, Chidamber and Kemerer): its methods plus
    /// the distinct other methods they call, told apart by name alone; off unless configured.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per type with too large a response set.
    private static func responseForClass(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        typeFindings("response-for-class", summary, file: file, context: context) { type, design, parameters in
            let limit = parameters.int("max", default: 50)
            let own = Set(design.methods.map(\.name)), called = Set(design.methods.flatMap(\.calls)).subtracting(own)
            guard own.count + called.count > limit else { return nil }
            return "Type \"\(type.name)\" has response for a class (RFC) \(own.count + called.count): \(own.count) "
                + "methods plus \(called.count) distinct methods they call, over the \(limit) limit."
        }
    }

    /// Runs one opt-in check over every measured type outside test suites.
    ///
    /// - Parameters:
    ///   - ruleID: The rule.
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    ///   - check: Builds a type's finding message from its design facts and the rule's parameters, or `nil`.
    /// - Returns: One finding per type the check describes, on the type's first line.
    private static func typeFindings(
        _ ruleID: String, _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext,
        check: (CollectedType, TypeDesign, RuleParameters) -> String?
    ) -> [Finding] {
        guard let settings = enabledSettings(ruleID, optIn: true, context: context) else { return [] }
        return designedTypes(summary).compactMap { type, design in
            check(type, design, settings.parameters).map {
                finding(ruleID, type.startLine, $0, settings.severity, file)
            }
        }
    }

    /// Runs one opt-in check over every method of every measured type outside test suites.
    ///
    /// - Parameters:
    ///   - ruleID: The rule.
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    ///   - check: Builds a method's finding message from it, its type's design facts, and the rule's
    ///     parameters, or `nil`.
    /// - Returns: One finding per method the check describes, on the method's line.
    private static func methodFindings(
        _ ruleID: String, _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext,
        check: (MethodDesign, TypeDesign, RuleParameters) -> String?
    ) -> [Finding] {
        guard let settings = enabledSettings(ruleID, optIn: true, context: context) else { return [] }
        return designedTypes(summary).flatMap { _, design in
            design.methods.compactMap { method in
                check(method, design, settings.parameters).map {
                    finding(ruleID, method.line, $0, settings.severity, file)
                }
            }
        }
    }

    /// Flags every type that's a god class by the Lanza–Marinescu formula, for `god-class` with
    /// `formula` set to `lanza-marinescu`; test files are skipped.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - settings: The `god-class` rule's resolved settings.
    /// - Returns: One finding per god class.
    static func lanzaMarinescuGodClasses(
        _ summary: DeclarationSummary, file: SourceFile, settings: RuleSettings
    ) -> [Finding] {
        guard !TextMatching.isTestPath(file.path) else { return [] }
        return summary.types.compactMap { type in
            lanzaMarinescuViolation(type, settings.parameters).map {
                finding(godClassRuleID, type.startLine, $0, settings.severity, file)
            }
        }
    }

    /// Checks a type against the Lanza–Marinescu god-class formula: WMC at least `minWMC` (VERY HIGH),
    /// ATFD at least `minATFD` (more than FEW), and TCC under `minTCC` (a third). A type where fewer than two
    /// methods touch a field has TCC 0.
    ///
    /// - Parameters:
    ///   - type: The collected type.
    ///   - parameters: The `god-class` rule's parameters.
    /// - Returns: The finding message, or `nil` if any of the three conditions fails or it's unmeasured.
    static func lanzaMarinescuViolation(_ type: CollectedType, _ parameters: RuleParameters) -> String? {
        guard let structure = type.structure, let design = type.design, !isTestTypeName(type.name) else { return nil }
        let (minWMC, minATFD) = (parameters.int("minWMC", default: 47), parameters.int("minATFD", default: 6))
        let minTCC = parameters.double("minTCC", default: 1.0 / 3.0), wmc = structure.weightedMethods
        let tcc = CohesionGraph.classCohesion(structure.methods, fields: structure.fieldNames)?.tight ?? 0
        let atfd = design.foreignDataAccesses
        guard wmc >= minWMC, atfd >= minATFD, tcc < minTCC else { return nil }
        return "Type \"\(type.name)\" is a god class by the Lanza–Marinescu formula: WMC \(wmc) (at least \(minWMC)), "
            + "ATFD \(atfd) (at least \(minATFD)), and TCC \(tenths(tcc)) (under \(tenths(minTCC)))."
    }

    /// Formats a ratio as a percentage to one decimal place, so 0.329 and a third read differently.
    ///
    /// - Parameter ratio: A value from 0 to 1.
    /// - Returns: Its text, such as `32.9%`.
    private static func tenths(_ ratio: Double) -> String {
        String(format: "%.1f%%", ratio * 100)
    }

    /// Flags every instance method that reads at least `minAccesses` data members of one other object, more
    /// than twice as many as the members of its own type it uses (Marinescu's LAA under a third); off unless
    /// configured. The other object is a parameter, local, or loop variable, told apart by name: not a field,
    /// and not a settings bag named like `options`, `config`, or `context`. Its data is the properties and
    /// `getX()` getters the method reads: not writes, other calls, library accessors like `count`, or values
    /// copied as is into a constructor call. Initializers, type-level methods, test files, and methods whose
    /// names say they exist to read another object (`==`, `hash`, `encode`, `visit…`, `from…`, `to…`,
    /// `make…`, …) are skipped.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per envious method.
    private static func featureEnvy(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        methodFindings("feature-envy", summary, file: file, context: context) { method, design, parameters in
            let fields = Set(design.fields.map(\.name))
            return envyMessage(method, fields: fields, minimum: parameters.int("minAccesses", default: 5))
        }
    }

    /// Checks one method for feature envy.
    ///
    /// - Parameters:
    ///   - method: The method.
    ///   - fields: Its type's field names, which aren't other objects.
    ///   - minimum: The fewest data members of one object to report.
    /// - Returns: The finding message, or `nil`.
    private static func envyMessage(_ method: MethodDesign, fields: Set<String>, minimum: Int) -> String? {
        guard method.kind == .instance, !TextMatching.matches(envyExempt, method.name) else { return nil }
        let others = method.foreignData.filter {
            !fields.contains($0.key) && !method.ownMembers.contains($0.key) && !settingsBagNames.contains($0.key)
        }
        guard let (receiver, members) = others.max(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) }),
              members.count >= minimum, members.count > 2 * method.ownMembers.count else { return nil }
        return "Method \"\(method.name)\" uses \(members.count) members of \"\(receiver)\" but "
            + "\(method.ownMembers.count) of its own type (feature envy); move it to \"\(receiver)\"'s type."
    }

    /// Names that hold a bag of settings rather than an object with behavior to move code into.
    private static let settingsBagNames: Set<String> = [
        "options", "opts", "args", "arguments", "config", "configuration", "conf", "cfg", "settings", "context",
        "ctx", "env", "environment", "params", "parameters", "flags", "prefs", "preferences", "kwargs"
    ]

    private static let envyExempt = TextMatching.regex(
        #"^(==|!=|<|>|<=|>=|__\w+__|_*(hash|equals|isEqual|compare|compareTo|encode|decode|describe|description|"#
            + #"render|format|serialize|deserialize|copy|clone|visit|from|to|make|map|convert|as|build|create|"#
            + #"update|apply|merge|assign|populate|configure|test|parse|validate|check|assert|expect|print|log|"#
            + #"dump|write|emit|handle|on)([A-Z_].*)?)$"#
    )

    /// Flags every private, mutable field declared without a value that only one method uses, where that
    /// method's first use is an unconditional top-level assignment and it reads the field afterward: the
    /// field is a local variable in disguise. Types an extension in the file adds to, and the variant where
    /// one method sets the field for another that always runs after it, aren't checked.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per temporary field.
    private static func temporaryFields(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        guard let settings = enabledSettings("temporary-field", context: context) else { return [] }
        return designedTypes(summary).filter { $0.0.structure?.isComplete != false }.flatMap { type, design in
            design.fields.compactMap { field in
                soleUser(of: field, in: design).map {
                    finding("temporary-field", field.line, temporaryMessage(field, type, $0), settings.severity, file)
                }
            }
        }
    }

    /// Describes a temporary field.
    ///
    /// - Parameters:
    ///   - field: The field.
    ///   - type: Its type.
    ///   - method: The one method that uses it.
    /// - Returns: The finding message.
    private static func temporaryMessage(
        _ field: FieldDeclaration, _ type: CollectedType, _ method: MethodDesign
    ) -> String {
        "Field \"\(field.name)\" of \"\(type.name)\" is set and read only inside \"\(method.name)\" (temporary field); "
            + "make it a local variable there."
    }

    /// Finds the one method a temporary field lives in.
    ///
    /// - Parameters:
    ///   - field: The field.
    ///   - design: Its type's design facts.
    /// - Returns: The method, or `nil` if the field isn't temporary.
    private static func soleUser(of field: FieldDeclaration, in design: TypeDesign) -> MethodDesign? {
        guard field.isTemporaryCandidate else { return nil }
        let users = design.methods.filter { $0.fieldAccesses.contains { $0.field == field.name } }
        guard users.count == 1, let user = users.first, user.kind == .instance else { return nil }
        let accesses = user.fieldAccesses.filter { $0.field == field.name }
        guard let first = accesses.first, first.kind == .assign, first.isTopLevel,
              accesses.contains(where: { $0.kind == .read }) else { return nil }
        return user
    }

    /// Flags every instance method that changes its own fields (assigning one, or calling a mutating method
    /// like `append` on one) and also returns a computed value; off unless configured. Fluent methods returning
    /// `self`/`this`, methods returning only constants (a status such as `true` or `.visitChildren`), Swift
    /// `@discardableResult`, `mutating`, and `override` methods (and TS `override`), lazy caches (every changed
    /// field is checked in an `if`/`guard` condition or Python `hasattr` first), dunder methods, and names that
    /// promise both (`pop`, `next`, `dequeue`, `take`, `increment`, `advance`, …) are skipped.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per method that's both a command and a query.
    private static func commandQuerySeparation(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        methodFindings("command-query-separation", summary, file: file, context: context) { method, _, _ in
            commandQueryMessage(method)
        }
    }

    /// Checks one method for command–query separation.
    ///
    /// - Parameter method: The method.
    /// - Returns: The finding message, or `nil`.
    private static func commandQueryMessage(_ method: MethodDesign) -> String? {
        let written = method.writtenFields
        guard method.kind == .instance, method.returnsValue, !method.isMutating, !method.isOverride, !written.isEmpty,
              !written.isSubset(of: method.conditionFields),
              !TextMatching.matches(commandQueryExempt, method.name) else { return nil }
        let names = written.sorted().map { "\"\($0)\"" }.joined(separator: ", ")
        return "Method \"\(method.name)\" both changes \(names) and returns a value (command–query separation); "
            + "split it into a command and a query."
    }

    private static let commandQueryExempt = TextMatching.regex(
        #"^(__\w+__|_*(pop|push|next|dequeue|enqueue|take|increment|decrement|incr|decr|advance|consume|eat|"#
            + #"read|remove|insert|append|add|put|poll|drain|shift|unshift|splice|allocate|acquire|reserve|claim|"#
            + #"generate|toggle|swap|replace|getOrCreate|getOrAdd|getOrInsert|intern|register|flush|finish|"#
            + #"finalize|build|commit|emit|step|tick|skip|expect|accept|match|scan|lex|getAndIncrement|"#
            + #"incrementAndGet)([A-Z_].*)?)$"#
    )

    /// Flags every function with at least `minParameters` string or number parameters, and every
    /// parameter or field whose name says it's an ID, amount, price, currency, date, time, email, URL,
    /// or phone number but whose declared type is a plain string or number; off unless configured.
    /// Only explicit type annotations count; booleans are left to `boolean-parameter`.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per primitive-heavy function and per stringly typed slot.
    private static func primitiveObsession(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        guard let settings = enabledSettings("primitive-obsession", optIn: true, context: context) else { return [] }
        let minimum = settings.parameters.int("minParameters", default: 4)
        let words = Set(settings.parameters.stringList("words", default: defaultPrimitiveWords))
        let fields = designedTypes(summary).flatMap(\.1.fields).filter { isStringly($0.name, $0.typeName, words) }
        let messages = summary.functions.compactMap { primitiveMessage($0, minimum: minimum, words: words) }
            + fields.map { ($0.line, "Field \"\($0.name)\" is a plain \($0.typeName ?? "") (primitive obsession); "
                + "give it a domain type.") }
        return messages.map { finding("primitive-obsession", $0.0, $0.1, settings.severity, file) }
    }

    /// Checks one function's parameters: too many strings and numbers, or any stringly typed ID, amount, or date.
    ///
    /// - Parameters:
    ///   - function: The function.
    ///   - minimum: The fewest primitive parameters to report on count alone.
    ///   - words: The name words that call for a domain type.
    /// - Returns: The function's line and finding message, or `nil`.
    private static func primitiveMessage(
        _ function: CollectedFunction, minimum: Int, words: Set<String>
    ) -> (Int, String)? {
        let count = function.parameters.filter { isPrimitive($0.typeName) }.count
        if count >= minimum, !initializerNames.contains(function.name) {
            return (function.startLine, "Function \"\(function.name)\" takes \(count) string or number parameters "
                + "(primitive obsession); group related ones into a type.")
        }
        let stringly = function.parameters.filter { isStringly($0.name, $0.typeName, words) }
        return stringly.isEmpty ? nil : (function.startLine, stringlyMessage(function, stringly))
    }

    /// Describes a function's stringly typed parameters.
    ///
    /// - Parameters:
    ///   - function: The function.
    ///   - stringly: Its parameters whose names call for a domain type.
    /// - Returns: The finding message.
    private static func stringlyMessage(_ function: CollectedFunction, _ stringly: [CollectedName]) -> String {
        let listed = stringly.map { "\"\($0.name)\": \($0.typeName ?? "")" }.joined(separator: ", ")
        return "Function \"\(function.name)\" takes \(listed) as plain primitives (primitive obsession); "
            + "give \(stringly.count == 1 ? "it a domain type" : "them domain types")."
    }

    static let defaultPrimitiveWords = [
        "id", "uuid", "guid", "amount", "price", "cost", "money", "currency", "date", "timestamp", "email",
        "url", "uri", "phone", "iban", "zip", "postcode"
    ]

    /// Reports whether a parameter or field's name calls for a domain type that its primitive type isn't.
    ///
    /// - Parameters:
    ///   - name: The declared name, such as `userId`.
    ///   - typeName: Its declared type, if any.
    ///   - words: The name words that call for a domain type.
    /// - Returns: Whether its last word is one of `words` and its type is a plain string or number.
    private static func isStringly(_ name: String, _ typeName: String?, _ words: Set<String>) -> Bool {
        let nameWords = Self.words(of: name)
        guard let last = nameWords.last, words.contains(last), last != "id" || nameWords.count > 1 else { return false }
        return isPrimitive(typeName)
    }

    /// Splits a name into lowercase words, keeping an acronym whole, so `fromID`, `from_id`, and `fromId`
    /// all end in `id`.
    ///
    /// - Parameter name: The name.
    /// - Returns: Its words.
    private static func words(of name: String) -> [String] {
        let range = NSRange(name.startIndex..., in: name)
        return (wordPattern?.matches(in: name, range: range) ?? []).compactMap { Range($0.range, in: name) }
            .map { name[$0].lowercased() }
    }

    private static let wordPattern = TextMatching.regex("[A-Z]+(?![a-z])|[A-Z]?[a-z0-9]+")

    private static let initializerNames: Set<String> = ["init", "constructor", "__init__"]

    /// Reports whether a declared type is a plain string or number, possibly optional.
    ///
    /// - Parameter typeName: The type's source text, if declared.
    /// - Returns: Whether it's a string, integer, or floating-point type.
    private static func isPrimitive(_ typeName: String?) -> Bool {
        !TypeWords.categories(of: typeName).isDisjoint(with: [.string, .integer, .float])
    }
}
