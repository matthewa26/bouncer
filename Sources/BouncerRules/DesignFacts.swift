/// One read or write of a type's own field inside one of its methods, for `temporary-field`.
public struct FieldAccess: Sendable, Equatable {
    /// How a method touches a field.
    public enum Kind: Sendable, Equatable {
        /// Reads the field's value.
        case read
        /// Replaces the field's value with one that doesn't read it, as in `self.x = y`.
        case assign
        /// Changes the field using its old value: a compound assignment, `++`, or a mutating call.
        case mutate
    }

    public let field: String
    public let kind: Kind
    /// Whether it's a statement directly in the method's body, outside any branch, loop, or closure.
    public let isTopLevel: Bool

    /// Creates a field access.
    ///
    /// - Parameters:
    ///   - field: The field's name.
    ///   - kind: Whether it reads, assigns, or mutates the field.
    ///   - isTopLevel: Whether it's a statement directly in the method's body.
    public init(field: String, kind: Kind, isTopLevel: Bool = false) {
        self.field = field
        self.kind = kind
        self.isTopLevel = isTopLevel
    }
}

/// What one method of a type does with its own members and with other objects, for the design-smell
/// rules: feature envy, temporary field, command–query separation, RFC, and ATFD.
public struct MethodDesign: Sendable, Equatable {
    /// Whether a method belongs to instances, initializes them, or belongs to the type.
    public enum Kind: Sendable, Equatable {
        case instance
        case initializer
        case typeLevel
    }

    public let name: String
    public let line: Int
    public let kind: Kind
    /// The type's own members it names, through `self`/`this` or (Swift) implicitly.
    public let ownMembers: Set<String>
    /// For each other object it names (a parameter, local, or field), the data members it reads on it:
    /// properties and `getX()`-style getters, but not assignments or values copied as is into a constructor
    /// call. Keyed by the object's name.
    public let foreignData: [String: Set<String>]
    /// Its own field accesses, in source order.
    public let fieldAccesses: [FieldAccess]
    /// The names of the methods and functions it calls; constructors aren't included.
    public let calls: Set<String>
    /// Whether it returns a computed value: a non-`Void` result that isn't `self`/`this`, isn't marked
    /// discardable, and isn't only ever a constant such as `true` or an enum case.
    public let returnsValue: Bool
    /// The own fields its `if`/`guard` conditions read, as a lazy cache's `if cache == nil` does.
    public let conditionFields: Set<String>
    /// Whether it's a Swift `mutating` method, whose mutation the caller opts into with `var`.
    public let isMutating: Bool
    /// Whether it overrides a superclass method, whose signature it doesn't choose.
    public let isOverride: Bool

    /// Creates a method's design facts.
    ///
    /// - Parameters:
    ///   - name: The method's name.
    ///   - line: The 1-indexed line it's declared on.
    ///   - kind: Instance method, initializer, or type-level method.
    ///   - ownMembers: The own members it names.
    ///   - foreignData: The data members it uses on each other object.
    ///   - fieldAccesses: Its own field accesses, in source order.
    ///   - calls: The names of what it calls.
    ///   - returnsValue: Whether it returns a value.
    ///   - conditionFields: The own fields its `if`/`guard` conditions read.
    ///   - isMutating: Whether it's a Swift `mutating` method.
    ///   - isOverride: Whether it overrides a superclass method.
    public init(
        name: String, line: Int, kind: Kind = .instance, ownMembers: Set<String> = [],
        foreignData: [String: Set<String>] = [:], fieldAccesses: [FieldAccess] = [], calls: Set<String> = [],
        returnsValue: Bool = false, conditionFields: Set<String> = [], isMutating: Bool = false,
        isOverride: Bool = false
    ) {
        (self.name, self.line, self.kind) = (name, line, kind)
        (self.ownMembers, self.foreignData, self.fieldAccesses) = (ownMembers, foreignData, fieldAccesses)
        (self.calls, self.returnsValue) = (calls, returnsValue)
        (self.conditionFields, self.isMutating, self.isOverride) = (conditionFields, isMutating, isOverride)
    }

    /// The own fields it assigns or mutates.
    public var writtenFields: Set<String> {
        Set(fieldAccesses.filter { $0.kind != .read }.map(\.field))
    }
}

/// A field a type declares, or (TS/JS, Python) creates by assigning `this.x`/`self.x`.
public struct FieldDeclaration: Sendable, Equatable {
    public let name: String
    public let line: Int
    /// Its explicitly declared type's source text, if it has one.
    public let typeName: String?
    /// Whether it could be a temporary field: mutable, private (by modifier or a `_`/`#` name), with no
    /// value at its declaration, and no property wrapper, decorator, or `lazy`.
    public let isTemporaryCandidate: Bool

    /// Creates a field declaration.
    ///
    /// - Parameters:
    ///   - name: The field's name.
    ///   - line: The 1-indexed line it's declared (or first assigned) on.
    ///   - typeName: Its declared type, if any.
    ///   - isTemporaryCandidate: Whether it's mutable, private, and declared without a value.
    public init(name: String, line: Int, typeName: String? = nil, isTemporaryCandidate: Bool = false) {
        self.name = name
        self.line = line
        self.typeName = typeName
        self.isTemporaryCandidate = isTemporaryCandidate
    }
}

/// A class or struct's coupling and its methods' design facts, for CBO, RFC, ATFD, the Lanza–Marinescu
/// god-class formula, feature envy, temporary field, and command–query separation.
public struct TypeDesign: Sendable, Equatable {
    /// The other types its body names in type annotations, constructor calls, and static member access,
    /// excluding its own name, its nested types, and generic parameters. Library types are still here;
    /// the rules drop them per language.
    public let referencedTypes: Set<String>
    /// Every method, initializer, and type-level method its body declares.
    public let methods: [MethodDesign]
    /// Its fields.
    public let fields: [FieldDeclaration]

    /// Creates a type's design facts.
    ///
    /// - Parameters:
    ///   - referencedTypes: The other types it names.
    ///   - methods: Its methods and initializers.
    ///   - fields: Its fields.
    public init(referencedTypes: Set<String>, methods: [MethodDesign], fields: [FieldDeclaration]) {
        self.referencedTypes = referencedTypes
        self.methods = methods
        self.fields = fields
    }

    /// ATFD (Lanza and Marinescu): the distinct data members of other objects its methods use, counted
    /// per object name, since without types `a.count` and `b.count` may be different classes' data.
    public var foreignDataAccesses: Int {
        Set(methods.flatMap { method in
            method.foreignData.flatMap { receiver, members in members.map { "\(receiver).\($0)" } }
        }).count
    }
}
