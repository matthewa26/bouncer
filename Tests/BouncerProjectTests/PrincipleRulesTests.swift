import XCTest
import Foundation
import BouncerCore
@testable import BouncerProject

/// Builds structure facts tersely for the principle rule tests.
private enum Build {
    static func type(
        _ name: String, _ kind: TypeKind = .class, line: Int = 1, supers: [String] = [], fields: [String] = [],
        methods: [String] = [], refused: [String] = [], empty: [String] = [], configure: (inout TypeMembers) -> Void = { _ in }
    ) -> TypeFact {
        var members = TypeMembers(supertypes: supers, fields: fields, methods: methods, refused: refused, empty: empty)
        configure(&members)
        return TypeFact(name: name, line: line, kind: kind, members: members)
    }

    static func file(
        _ path: String, types: [TypeFact] = [], functions: [FunctionFact] = [],
        collaborations: [CollaborationFact] = [], exports: [ExportFact] = []
    ) -> FileFacts {
        let structure = StructureFacts(types: types, functions: functions, collaborations: collaborations)
        return FileFacts(path: path, contentHash: "h", module: ModuleFacts(imports: [], exports: exports, structure: structure))
    }
}

final class PrincipleRulesTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    private func findings(
        _ ruleID: String, _ files: [FileFacts], params: [String: RuleParameterValue] = [:], configured: Bool = false
    ) -> [Finding] {
        let settings = configured || !params.isEmpty
            ? [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: params))] : [:]
        let context = AnalysisContext(repoRoot: root, ruleSettings: settings)
        return ProjectRules().findings(for: files, targets: [], context: context).filter { $0.ruleID == ruleID }
    }

    private func places(_ found: [Finding]) -> [String] {
        found.map { "\(RepoPath.relative($0.filePath, to: root)):\($0.line)" }
    }

    // MARK: liskov-substitution

    private var exporters: [FileFacts] {
        let proto = Build.type("Exporter", .protocol, methods: ["export", "preview"])
        let pdf = Build.type("PDFExporter", line: 3, supers: ["Exporter"], methods: ["export", "preview"]) {
            $0.refusedOwn = ["preview"]
        }
        let fax = Build.type("FaxExporter", line: 6, supers: ["Exporter"], methods: ["export", "preview"]) {
            $0.refusedOwn = ["export"]
        }
        let base = Build.type("BaseExporter", line: 9, supers: ["Exporter"], methods: ["export"]) { $0.refusedOwn = ["export"] }
        let mock = Build.type("MockExporter", supers: ["Exporter"], methods: ["export"]) { $0.refusedOwn = ["export"] }
        return [Build.file("Sources/A/Exporter.swift", types: [proto]),
                Build.file("Sources/A/Impl.swift", types: [pdf, fax, base]),
                Build.file("Tests/ATests/Mocks.swift", types: [mock])]
    }

    func testFlagsConformersThatRefuseRequirementsButNotAbstractBasesOrTests() {
        let found = findings("liskov-substitution", exporters)
        XCTAssertEqual(places(found), ["Sources/A/Impl.swift:3", "Sources/A/Impl.swift:6"])
        XCTAssertEqual(found.first?.message, "\"PDFExporter\" implements Exporter.preview() only to throw or trap, so "
            + "it can't stand in wherever its supertype is expected (Liskov substitution). Implement the behavior, "
            + "or don't claim the supertype.")
    }

    func testRefusalsOfInheritedImplementationsAreLeftToRefusedBequest() {
        let parent = Build.type("Store", supers: ["Saving"], methods: ["save"])
        let saving = Build.type("Saving", .protocol, methods: ["save"])
        let child = Build.type("ReadOnlyStore", line: 4, supers: ["Store"], methods: ["save"], refused: ["save"]) {
            $0.overrides = ["save"]
        }
        let files = [Build.file("Sources/A/a.swift", types: [saving, parent, child])]
        XCTAssertTrue(findings("liskov-substitution", files).isEmpty)
        XCTAssertEqual(places(findings("refused-bequest", files)), ["Sources/A/a.swift:4"])
    }

    func testFlagsOverridesThatAddAPreconditionTheParentLacks() {
        let pricer = Build.type("Pricer", methods: ["price", "discount", "label"]) { $0.guarded = ["label"] }
        let wholesale = Build.type("WholesalePricer", line: 5, supers: ["Pricer"], methods: ["price", "label"]) {
            $0.guarded = ["price", "label"]
            $0.overrides = ["price", "label"]
        }
        let python = [Build.type("Codec", methods: ["encode"]),
                      Build.type("Codec", line: 3, supers: ["Codec"], methods: ["encode"]) { $0.guarded = ["encode"] }]
        let found = findings("liskov-substitution", [Build.file("Sources/A/p.swift", types: [pricer, wholesale]),
                                                     Build.file("lib/a.py", types: [python[0]]),
                                                     Build.file("lib/b.py", types: [python[1]])])
        XCTAssertEqual(places(found), ["Sources/A/p.swift:5"])
        XCTAssertTrue(found.first?.message.contains("adds a precondition to Pricer.price() that the parent lacks") == true)
    }

    // MARK: interface-segregation

    func testFlagsAProtocolMostlyStubbedByAConformerAndLeavesItsRefusalsToThisRule() {
        let storage = Build.type("Storage", .protocol, line: 2, methods: ["read", "write", "delete", "list", "flush", "lock"])
        let readOnly = Build.type("ReadOnlyStorage", .struct, line: 9, supers: ["Storage"], methods: storage.methods) {
            $0.emptyOwn = ["write", "delete", "flush"]
            $0.refusedOwn = ["lock"]
        }
        let partial = Build.type("PartialStorage", .struct, line: 20, supers: ["Storage"], methods: storage.methods) {
            $0.emptyOwn = ["flush", "lock"]
        }
        let files = [Build.file("Sources/A/Storage.swift", types: [storage, readOnly, partial])]
        let found = findings("interface-segregation", files)
        XCTAssertEqual(places(found), ["Sources/A/Storage.swift:2"])
        XCTAssertEqual(found.first?.message, "\"Storage\" has 6 requirements, and conformers implement most of them "
            + "as empty or throwing stubs (ReadOnlyStorage stubs 4); split it into smaller protocols that clients use "
            + "whole.")
        XCTAssertTrue(findings("liskov-substitution", files).isEmpty)
        XCTAssertTrue(findings("interface-segregation", files, params: ["minRequirements": .int(7)]).isEmpty)
    }

    func testAbstractClassRequirementsAreItsStubbedMethods() {
        let carrier = Build.type("Carrier", .abstractClass, methods: ["quote", "ship", "track", "cancel", "insure", "name"],
                                 empty: ["quote", "ship", "track", "cancel", "insure"])
        let pigeon = Build.type("PigeonPost", line: 30, supers: ["Carrier"], methods: ["quote", "ship", "track", "cancel", "insure"],
                                refused: ["insure"], empty: ["track", "cancel"])
        let found = findings("interface-segregation", [Build.file("ship/carriers.py", types: [carrier, pigeon])])
        XCTAssertEqual(found.first?.message.contains("\"Carrier\" has 5 requirements"), true)
    }

    // MARK: single-override-subclass

    func testFlagsFieldlessSubclassesOverridingOneRealMethodWhenConfigured() {
        let renderer = Build.type("Renderer", methods: ["render", "header"])
        let shouting = Build.type("ShoutingRenderer", line: 4, supers: ["Renderer"], methods: ["render"]) { $0.overrides = ["render"] }
        let counting = Build.type("CountingRenderer", line: 8, supers: ["Renderer"], fields: ["count:Int"], methods: ["render"]) {
            $0.overrides = ["render"]
        }
        let extra = Build.type("ExtraRenderer", line: 12, supers: ["Renderer"], methods: ["footer"])
        let files = [Build.file("Sources/A/r.swift", types: [renderer, shouting, counting, extra])]
        XCTAssertTrue(findings("single-override-subclass", files).isEmpty)
        let found = findings("single-override-subclass", files, configured: true)
        XCTAssertEqual(places(found), ["Sources/A/r.swift:4"])
        XCTAssertEqual(found.first?.message, "\"ShoutingRenderer\" subclasses \"Renderer\" only to override render(); "
            + "pass the varying behavior to \"Renderer\" (a closure or strategy) instead of subclassing.")
        let python = [Build.type("Scale", methods: ["weigh"]), Build.type("PostalScale", line: 5, supers: ["Scale"], methods: ["weigh"])]
        XCTAssertEqual(places(findings("single-override-subclass", [Build.file("s.py", types: python)], configured: true)),
                       ["s.py:5"])
    }

    // MARK: inappropriate-intimacy

    func testFlagsTwoTypesInDifferentFilesReadingEachOthersFields() {
        let order = Build.type("Order", line: 2, fields: ["total:Int", "discount:Int", "lines"])
        let customer = Build.type("Customer", line: 3, fields: ["points:Int", "tier:Int", "name:String"])
        let files = [
            Build.file("Sources/A/Order.swift", types: [order], collaborations: [
                CollaborationFact(owner: "Order", line: 2, uses: ["Customer.points", "Customer.tier", "Customer.greet"])
            ]),
            Build.file("Sources/A/Customer.swift", types: [customer], collaborations: [
                CollaborationFact(owner: "Customer", line: 3, uses: ["Order.total", "Order.discount"])
            ])
        ]
        let found = findings("inappropriate-intimacy", files)
        XCTAssertEqual(places(found), ["Sources/A/Customer.swift:3"])
        XCTAssertEqual(found.first?.message, "\"Customer\" and \"Order\" (Sources/A/Order.swift) read each other's "
            + "fields (Order.discount, Order.total; Customer.points, Customer.tier); move the behavior next to the "
            + "data it uses, or merge the two.")
        XCTAssertTrue(findings("inappropriate-intimacy", files, params: ["minFields": .int(3)]).isEmpty)
    }

    func testPublicSwiftFieldsAreNotInternalsButUnderscoredPythonNamesAre() {
        let exported = [ExportFact(name: "points", line: 4), ExportFact(name: "tier", line: 5)]
        let swift = [
            Build.file("Sources/A/Order.swift", types: [Build.type("Order", fields: ["total", "discount"])],
                       collaborations: [CollaborationFact(owner: "Order", line: 1, uses: ["Customer.points", "Customer.tier"])]),
            Build.file("Sources/A/Customer.swift", types: [Build.type("Customer", fields: ["points", "tier"])],
                       collaborations: [CollaborationFact(owner: "Customer", line: 1, uses: ["Order.total", "Order.discount"])],
                       exports: exported)
        ]
        XCTAssertTrue(findings("inappropriate-intimacy", swift).isEmpty)
        let python = [
            Build.file("ship/dispatch.py", types: [Build.type("Dispatcher")],
                       collaborations: [CollaborationFact(owner: "Dispatcher", line: 1, uses: ["Parcel._code", "Parcel._status"])]),
            Build.file("ship/parcel.py", types: [Build.type("Parcel")],
                       collaborations: [CollaborationFact(owner: "Parcel", line: 1, uses: ["Dispatcher._queue", "Dispatcher._busy", "Dispatcher.__len__"])])
        ]
        XCTAssertEqual(places(findings("inappropriate-intimacy", python)), ["ship/dispatch.py:1"])
    }

    // MARK: dependency-inversion

    private var checkout: [FileFacts] {
        let types = [Build.type("PaymentGateway", .protocol, methods: ["charge"]),
                     Build.type("StripeGateway", line: 2, supers: ["PaymentGateway"]),
                     Build.type("InventoryService", .struct, line: 3), Build.type("Money", .struct, line: 4),
                     Build.type("ChargeError", line: 5), Build.type("CheckoutFlow", line: 6),
                     Build.type("RefundFlow", line: 7), Build.type("ShopAssembly", line: 8)]
        let constructs = ["StripeGateway", "InventoryService", "Money", "ChargeError"]
        return [Build.file("Sources/A/Checkout.swift", types: types, functions: [
            FunctionFact(name: "RefundFlow.init", line: 7, parameters: ["gateway:PaymentGateway"])
        ], collaborations: ["CheckoutFlow", "RefundFlow", "ShopAssembly"].enumerated().map { offset, owner in
            CollaborationFact(owner: owner, line: 6 + offset, constructs: constructs)
        })]
    }

    func testFlagsKeptConstructionsOfImplementationsAndServicesWhenConfigured() {
        XCTAssertTrue(findings("dependency-inversion", checkout).isEmpty)
        let found = findings("dependency-inversion", checkout, configured: true)
        XCTAssertEqual(places(found), ["Sources/A/Checkout.swift:6", "Sources/A/Checkout.swift:7"])
        XCTAssertEqual(found.first?.message, "\"CheckoutFlow\" constructs and keeps InventoryService, StripeGateway "
            + "(implementing PaymentGateway) itself; take them (or their abstractions) through the initializer so callers can "
            + "substitute a different implementation.")
        XCTAssertEqual(found.last?.message, "\"RefundFlow\" constructs and keeps InventoryService itself; take it (or "
            + "its abstraction) through the initializer so callers can substitute a different implementation.")
    }

    func testLanguageProtocolsAreNotServiceSeams() {
        let types = [Build.type("AbstractContextManager", .abstractClass, methods: ["__enter__", "__exit__"]),
                     Build.type("ExitStack", line: 2, supers: ["AbstractContextManager"]), Build.type("Patcher", line: 3)]
        let files = [Build.file("lib/ctx.py", types: types,
                                collaborations: [CollaborationFact(owner: "Patcher", line: 3, constructs: ["ExitStack"])])]
        XCTAssertTrue(findings("dependency-inversion", files, configured: true).isEmpty)
    }

    // MARK: alternative-interfaces

    private func method(_ owner: String, _ name: String, _ parameters: [String], _ returns: String? = nil) -> FunctionFact {
        FunctionFact(name: name, line: 1, parameters: parameters, owner: owner, returns: returns)
    }

    func testFlagsUnrelatedTypesWithMatchingShapesUnderDifferentNamesWhenConfigured() {
        let email = ["sendEmail": ["to:Address", "body:Letter"], "trackEmail": ["id:TrackingID"], "cancelEmail": ["r:Receipt"]]
        let mail = ["deliver": ["recipient:Address", "text:Letter"], "status": ["id:TrackingID"], "revoke": ["r:Receipt"]]
        let returns = ["sendEmail": "Receipt", "deliver": "Receipt"]
        let files = [
            Build.file("Sources/A/Email.swift", types: [Build.type("EmailSender", line: 3)],
                       functions: email.map { method("EmailSender", $0.key, $0.value, returns[$0.key]) }
                           + [method("EmailSender", "ping", [])]),
            Build.file("Sources/A/Mail.swift", types: [Build.type("MailDispatcher", line: 5)],
                       functions: mail.map { method("MailDispatcher", $0.key, $0.value, returns[$0.key]) }),
            Build.file("Sources/A/Sms.swift", types: [Build.type("SmsSender", line: 7, supers: ["EmailSender"])],
                       functions: email.map { method("SmsSender", $0.key, $0.value, returns[$0.key]) })
        ]
        XCTAssertTrue(findings("alternative-interfaces", files).isEmpty)
        let found = findings("alternative-interfaces", files, configured: true)
        // SmsSender inherits EmailSender, so that pair is related; it's still an alternative to MailDispatcher.
        XCTAssertEqual(places(found), ["Sources/A/Email.swift:3", "Sources/A/Mail.swift:5"])
        XCTAssertEqual(found.first?.message, "\"EmailSender\" and \"MailDispatcher\" (Sources/A/Mail.swift) have 3 "
            + "methods with the same signatures under different names (sendEmail()/deliver(), cancelEmail()/revoke(), "
            + "trackEmail()/status()); if they do the same job, give them one protocol and one set of names.")
        XCTAssertTrue(findings("alternative-interfaces", files, params: ["minMatches": .int(4)]).isEmpty)
    }

    func testShapesNeedEveryParameterTypedAndAtLeastOne() {
        XCTAssertEqual(Signature.shape(of: FunctionFact(name: "f", line: 1, parameters: ["a:Int", "b:[String]"])),
                       "(Int,[String])->Void")
        XCTAssertNil(Signature.shape(of: FunctionFact(name: "f", line: 1, parameters: ["a", "b:Int"])))
        XCTAssertNil(Signature.shape(of: FunctionFact(name: "f", line: 1, returns: "Int")))
    }

    // MARK: cache

    func testFactsStoreRoundTripsTheNewShapeAndRebuildsVersionFour() throws {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("principles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }
        let type = Build.type("A", supers: ["P"], methods: ["m", "n"]) {
            ($0.overrides, $0.refusedOwn, $0.emptyOwn, $0.guarded) = (["m"], ["n"], ["o"], ["m"])
        }
        let stored = Build.file("a.swift", types: [type], functions: [method("A", "m", ["x:Int"], "Bool")],
                                collaborations: [CollaborationFact(owner: "A", line: 1, uses: ["B.x"], constructs: ["C"])])
        try JSONFactsStore(repoRoot: repo).save([stored])
        XCTAssertEqual(JSONFactsStore(repoRoot: repo).cachedFacts(path: "a.swift", contentHash: "h"), stored)
        let cacheFile = repo.appendingPathComponent(".bouncer-cache/facts.json")
        let json = try String(contentsOf: cacheFile, encoding: .utf8)
        XCTAssertTrue(json.contains("\"refusedOwn\":[\"n\"]") && json.contains("\"collaborations\""))
        try json.replacingOccurrences(of: "\"version\":5", with: "\"version\":4")
            .write(to: cacheFile, atomically: true, encoding: .utf8)
        XCTAssertNil(JSONFactsStore(repoRoot: repo).cachedFacts(path: "a.swift", contentHash: "h"))
    }

    func testOlderFactsWithoutTheNewListsStillDecode() throws {
        let json = #"{"name":"A","line":1,"kind":"class","methods":["m"]}"#
        let type = try JSONDecoder().decode(TypeFact.self, from: Data(json.utf8))
        XCTAssertEqual(type.overrides + type.refusedOwn + type.emptyOwn + type.guarded, [])
        let function = try JSONDecoder().decode(FunctionFact.self, from: Data(#"{"name":"f","line":1,"parameters":[]}"#.utf8))
        XCTAssertNil(function.owner)
        let collaboration = try JSONDecoder().decode(CollaborationFact.self, from: Data(#"{"owner":"A","line":2}"#.utf8))
        XCTAssertEqual(collaboration, CollaborationFact(owner: "A", line: 2))
    }
}
