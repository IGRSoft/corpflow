// PreviewEnsurer.swift
//
// Reference implementation of the preview-ensurer Swift executable.
// Invoked by the apple-canvas adapter via:
//
//   swift run --package-path skills/preview-ensurer/references/reference-impl PreviewEnsurer \
//     --modified-files <newline-list-via-stdin-or-arg> \
//     [--auto-add true|false] \
//     [--view ModuleType]
//
// Returns JSON to stdout matching the contract in:
//   skills/preview-ensurer/SKILL.md § Contract (canonical signature)
//
// AR decisions referenced:
//   ad2 — swift-syntax pinned .upToNextMajor(from: "510.0.0")
//   ad4 — in-source write (no staged patches)
//   ad8 — errors[] non-empty bubbles to apple-canvas as missing_input
//
// SwiftSyntax patterns: see references/view-detection.md
// Mock-arg derivation:  see references/mock-data-strategy.md

import Foundation
import SwiftSyntax
import SwiftParser

// MARK: - Result types

struct ViewResult: Codable {
    let file: String
    let type: String
    let has_preview: Bool
    let action: String          // "found" | "added" | "skipped"
    let reason: String?
    let mock_strategy: String?
    let lines_added: Int?       // populated only when action == "added"
}

struct EnsureResult: Codable {
    let views: [ViewResult]
    let errors: [String]
}

// MARK: - View detection visitor

final class ViewDetector: SyntaxVisitor {

    struct Detected {
        let typeName: String
        let parameters: [(label: String?, type: String)]  // nil label = unlabeled (_) param
    }

    private(set) var viewTypes: [Detected] = []
    private(set) var hasPreview: Bool = false
    private(set) var hasPreviewProvider: Bool = false
    private var depth: Int = 0

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    // Pattern 1, 2 — struct/class/actor with View conformance
    // NOTE: depth is incremented here and decremented in visitPost — NOT via defer.
    // SyntaxVisitor visits children after visit() returns, so defer would fire
    // before children are walked, causing all nested types to appear at depth 1.
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        depth += 1
        if depth == 1, declaresView(node.inheritanceClause) {
            viewTypes.append(extractParameters(typeName: node.name.text, members: node.memberBlock.members))
        }
        // Detect PreviewProvider legacy form (Pattern 4)
        if declaresInheritance(node.inheritanceClause, name: "PreviewProvider") {
            hasPreviewProvider = true
        }
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        depth -= 1
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        depth += 1
        if depth == 1, declaresView(node.inheritanceClause) {
            viewTypes.append(extractParameters(typeName: node.name.text, members: node.memberBlock.members))
        }
        if declaresInheritance(node.inheritanceClause, name: "PreviewProvider") {
            hasPreviewProvider = true
        }
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        depth -= 1
    }

    // Pattern 3 — extension X: View
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        depth += 1
        if depth == 1, declaresView(node.inheritanceClause) {
            // v1: only register the extension target name; cross-file extension
            // resolution is out of scope.
            let typeName = node.extendedType.trimmedDescription
            viewTypes.append(Detected(typeName: typeName, parameters: []))
        }
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        depth -= 1
    }

    // Pattern 5 — #Preview macro
    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        if node.macroName.text == "Preview" {
            hasPreview = true
        }
        return .visitChildren
    }

    override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.macroName.text == "Preview" {
            hasPreview = true
        }
        return .visitChildren
    }

    // MARK: - Helpers

    private func declaresView(_ clause: InheritanceClauseSyntax?) -> Bool {
        guard let clause else { return false }
        for inherited in clause.inheritedTypes {
            let name = inherited.type.trimmedDescription
            if name == "View" || name == "SwiftUI.View" || name.hasSuffix(".View") {
                return true
            }
        }
        return false
    }

    private func declaresInheritance(_ clause: InheritanceClauseSyntax?, name: String) -> Bool {
        guard let clause else { return false }
        return clause.inheritedTypes.contains { $0.type.trimmedDescription == name }
    }

    private func extractParameters(
        typeName: String,
        members: MemberBlockItemListSyntax
    ) -> Detected {
        // Walk for explicit init first; fall back to synthesized memberwise init
        // inferred from stored `VariableDeclSyntax` properties.
        var params: [(String?, String)] = []

        for member in members {
            if let initDecl = member.decl.as(InitializerDeclSyntax.self) {
                for p in initDecl.signature.parameterClause.parameters {
                    // firstName == "_" means the parameter has no external call-site label.
                    // Use nil so generatePreviewBlock emits a positional argument (no "label:").
                    let label: String? = (p.firstName.text == "_") ? nil : p.firstName.text
                    let type  = p.type.trimmedDescription
                    params.append((label, type))
                }
                // First explicit init wins.
                return Detected(typeName: typeName, parameters: params)
            }
        }

        // No explicit init — infer from stored properties.
        for member in members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            // Skip computed properties and `static` / `class` storage.
            let isStatic = varDecl.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
                        || varDecl.modifiers.contains { $0.name.tokenKind == .keyword(.class) }
            if isStatic { continue }

            // Property-wrapper attribute detection (@Binding / @State / @StateObject / @EnvironmentObject / @Environment).
            // SwiftUI's memberwise init exposes ONLY `@Binding`-wrapped props (as Binding<T>);
            // @State / @StateObject / @EnvironmentObject / @Environment are NOT init params.
            var hasBindingWrapper = false
            var hasNonInitWrapper = false
            for attr in varDecl.attributes {
                guard let attribute = attr.as(AttributeSyntax.self) else { continue }
                let name = attribute.attributeName.trimmedDescription
                switch name {
                case "Binding":
                    hasBindingWrapper = true
                case "State", "StateObject", "EnvironmentObject", "Environment", "FocusState":
                    hasNonInitWrapper = true
                default:
                    break
                }
            }
            if hasNonInitWrapper { continue }

            for binding in varDecl.bindings {
                // Skip properties with default values from the synthesized memberwise init —
                // they don't appear in the init signature as required params.
                guard binding.initializer == nil else { continue }
                guard binding.accessorBlock == nil else { continue }  // computed
                guard let storedType = binding.typeAnnotation?.type.trimmedDescription else { continue }
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                // @Binding var x: T → init param type is Binding<T>
                let type = hasBindingWrapper ? "Binding<\(storedType)>" : storedType
                params.append((name, type))
            }
        }

        return Detected(typeName: typeName, parameters: params)
    }
}

// MARK: - Mock-arg derivation

enum MockStrategy: String {
    case bindingConstant = "binding-constant"
    case optionalNil     = "optional-nil"
    case mockFound       = "mock-found"
    case previewTBD      = "preview-tbd"
    case concreteInit    = "concrete-init"
}

struct MockArg {
    let expr: String
    let strategy: MockStrategy
    let skipReason: String?
}

func deriveMockArg(for type: String, in projectRoot: URL) -> MockArg {
    let t = type.trimmingCharacters(in: .whitespaces)

    // Binding<U>
    if let inner = stripGeneric(t, prefix: "Binding") {
        let u = inner.trimmingCharacters(in: .whitespaces)
        switch u {
        case "Bool":              return MockArg(expr: ".constant(false)", strategy: .bindingConstant, skipReason: nil)
        case "Int":               return MockArg(expr: ".constant(0)",     strategy: .bindingConstant, skipReason: nil)
        case "Double", "Float", "CGFloat":
                                  return MockArg(expr: ".constant(0)",     strategy: .bindingConstant, skipReason: nil)
        case "String":            return MockArg(expr: ".constant(\"\")",  strategy: .bindingConstant, skipReason: nil)
        default: break
        }
        if u.hasSuffix("?") || u.hasPrefix("Optional<") {
            return MockArg(expr: ".constant(nil)", strategy: .bindingConstant, skipReason: nil)
        }
        if u.hasPrefix("Array<") || u.hasPrefix("[") {
            return MockArg(expr: ".constant([])", strategy: .bindingConstant, skipReason: nil)
        }
        return MockArg(expr: "", strategy: .previewTBD, skipReason: "binding_complex_type:\(u)")
    }

    // Optional / T?
    if t.hasSuffix("?") || t.hasPrefix("Optional<") {
        return MockArg(expr: "nil", strategy: .optionalNil, skipReason: nil)
    }

    // Closure type
    if t.contains("->") {
        return MockArg(expr: "", strategy: .previewTBD, skipReason: "closure_unsupported")
    }

    // Generic / AnyView / opaque
    if t.hasPrefix("some ") || t.hasPrefix("any ") || t == "AnyView" {
        return MockArg(expr: "", strategy: .previewTBD, skipReason: "generic_unsupported")
    }

    // Protocol mock convention — Source/Mocks/Mock<P>.swift
    let mockName = "Mock\(t)"
    let candidates = [
        projectRoot.appendingPathComponent("Source/Mocks/\(mockName).swift"),
        projectRoot.appendingPathComponent("Sources/Mocks/\(mockName).swift"),
        projectRoot.appendingPathComponent("Mocks/\(mockName).swift"),
    ]
    if candidates.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
        return MockArg(expr: "\(mockName)()", strategy: .mockFound, skipReason: nil)
    }

    // Heuristic for concrete struct with no-arg init — accept any capitalized
    // simple identifier. The caller's `swift -frontend -parse` smoke catches
    // false positives.
    if isSimpleIdentifier(t), t.first?.isUppercase == true {
        return MockArg(expr: "\(t)()", strategy: .concreteInit, skipReason: nil)
    }

    return MockArg(expr: "", strategy: .previewTBD, skipReason: "unsupported_init_signature:\(t)")
}

private func stripGeneric(_ s: String, prefix: String) -> String? {
    let pat = "\(prefix)<"
    guard s.hasPrefix(pat), s.hasSuffix(">") else { return nil }
    return String(s.dropFirst(pat.count).dropLast())
}

private func isSimpleIdentifier(_ s: String) -> Bool {
    !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
}

// MARK: - Generation

func generatePreviewBlock(
    typeName: String,
    args: [(label: String?, expr: String)]
) -> String {
    // Format a single argument: labeled ("name: value") or positional ("value").
    func argFragment(_ label: String?, _ expr: String) -> String {
        guard let l = label else { return expr }
        return "\(l): \(expr)"
    }

    if args.isEmpty {
        return "\n#Preview {\n    \(typeName)()\n}\n"
    }
    if args.count == 1 {
        let (label, expr) = args[0]
        return "\n#Preview {\n    \(typeName)(\(argFragment(label, expr)))\n}\n"
    }
    let body = args.map { "        \(argFragment($0.label, $0.expr))" }.joined(separator: ",\n")
    return "\n#Preview {\n    \(typeName)(\n\(body)\n    )\n}\n"
}

// MARK: - File processing

func ensureFile(_ path: String, autoAdd: Bool, projectRoot: URL) -> (ViewResult, lines: Int) {
    let url = URL(fileURLWithPath: path)
    let typeFallback = url.deletingPathExtension().lastPathComponent

    // Read + parse
    let source: String
    do { source = try String(contentsOf: url, encoding: .utf8) } catch {
        return (ViewResult(file: path, type: typeFallback, has_preview: false,
                           action: "skipped", reason: "read_failed: \(error.localizedDescription)",
                           mock_strategy: nil, lines_added: nil), lines: 0)
    }

    let tree = Parser.parse(source: source)
    let detector = ViewDetector()
    detector.walk(tree)

    // A4 invariant: pre-existing preview → never overwrite
    if detector.hasPreview || detector.hasPreviewProvider {
        let firstType = detector.viewTypes.first?.typeName ?? typeFallback
        return (ViewResult(file: path, type: firstType, has_preview: true,
                           action: "found", reason: nil, mock_strategy: nil, lines_added: nil), lines: 0)
    }

    // Ambiguous (3+ top-level Views, no disambiguating --view)
    if detector.viewTypes.count >= 3 {
        return (ViewResult(file: path, type: detector.viewTypes.first?.typeName ?? typeFallback,
                           has_preview: false, action: "skipped",
                           reason: "ambiguous_view_target", mock_strategy: nil, lines_added: nil), lines: 0)
    }

    guard let target = detector.viewTypes.first else {
        return (ViewResult(file: path, type: typeFallback, has_preview: false,
                           action: "skipped", reason: "no_view_type_detected",
                           mock_strategy: nil, lines_added: nil), lines: 0)
    }

    // Derive mock args
    var generatedArgs: [(String?, String)] = []
    var summary: MockStrategy = .concreteInit
    var skipReason: String?
    for (label, type) in target.parameters {
        let m = deriveMockArg(for: type, in: projectRoot)
        if m.strategy == .previewTBD {
            summary = .previewTBD
            skipReason = m.skipReason
            break
        }
        generatedArgs.append((label, m.expr))
        // Track the most-specific strategy — first non-concrete wins for reporting.
        if summary == .concreteInit, m.strategy != .concreteInit {
            summary = m.strategy
        }
    }

    if summary == .previewTBD {
        return (ViewResult(file: path, type: target.typeName, has_preview: false,
                           action: "skipped",
                           reason: skipReason ?? "unsupported_init_signature",
                           mock_strategy: MockStrategy.previewTBD.rawValue, lines_added: nil), lines: 0)
    }

    if !autoAdd {
        return (ViewResult(file: path, type: target.typeName, has_preview: false,
                           action: "skipped", reason: "dry_run",
                           mock_strategy: summary.rawValue, lines_added: nil), lines: 0)
    }

    // Generate + append + parse-smoke
    let block = generatePreviewBlock(typeName: target.typeName, args: generatedArgs)
    let updated = source.hasSuffix("\n") ? source + block : source + "\n" + block

    do { try updated.write(to: url, atomically: true, encoding: .utf8) } catch {
        return (ViewResult(file: path, type: target.typeName, has_preview: false,
                           action: "skipped",
                           reason: "write_failed: \(error.localizedDescription)",
                           mock_strategy: summary.rawValue, lines_added: nil), lines: 0)
    }

    // Smoke test — `swift -frontend -parse`. On failure: rollback.
    if !runParseSmoke(path: path) {
        // Rollback
        try? source.write(to: url, atomically: true, encoding: .utf8)
        return (ViewResult(file: path, type: target.typeName, has_preview: false,
                           action: "skipped",
                           reason: "parse_failed_after_preview_add",
                           mock_strategy: summary.rawValue, lines_added: nil), lines: 0)
    }

    let linesAdded = block.filter { $0 == "\n" }.count
    return (ViewResult(file: path, type: target.typeName, has_preview: false,
                       action: "added", reason: nil,
                       mock_strategy: summary.rawValue, lines_added: linesAdded), lines: linesAdded)
}

private func runParseSmoke(path: String) -> Bool {
    let proc = Process()
    proc.launchPath = "/usr/bin/env"
    proc.arguments = ["xcrun", "swift", "-frontend", "-parse", path]
    proc.standardOutput = Pipe()
    proc.standardError = Pipe()
    do { try proc.run() } catch { return false }
    proc.waitUntilExit()
    return proc.terminationStatus == 0
}

// MARK: - Entry

struct CLI {
    var modifiedFiles: [String] = []
    var autoAdd: Bool = true
    var view: String?
    var projectRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

func parseCLI(_ argv: [String]) -> CLI {
    var cli = CLI()
    var i = 1
    while i < argv.count {
        let arg = argv[i]
        let next = (i + 1 < argv.count) ? argv[i + 1] : nil
        switch arg {
        case "--modified-files":
            // newline-separated list, OR a path to a file containing one path per line
            if let v = next {
                if FileManager.default.fileExists(atPath: v),
                   let contents = try? String(contentsOfFile: v, encoding: .utf8) {
                    cli.modifiedFiles = contents.split(whereSeparator: \.isNewline).map(String.init)
                } else {
                    cli.modifiedFiles = v.split(whereSeparator: \.isNewline).map(String.init)
                }
                i += 2
            } else { i += 1 }
        case "--auto-add":
            if let v = next {
                cli.autoAdd = (v.lowercased() == "true")
                i += 2
            } else { i += 1 }
        case "--view":
            cli.view = next
            i += 2
        case "--project-root":
            if let v = next {
                cli.projectRoot = URL(fileURLWithPath: v)
                i += 2
            } else { i += 1 }
        default:
            i += 1
        }
    }
    // If stdin has content and no --modified-files, read it
    if cli.modifiedFiles.isEmpty, isatty(fileno(stdin)) == 0 {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8) ?? ""
        cli.modifiedFiles = s.split(whereSeparator: \.isNewline).map(String.init)
    }
    return cli
}

let cli = parseCLI(CommandLine.arguments)

var views: [ViewResult] = []
var errors: [String] = []

// Only process *.swift files; never bootstrap on the scaffold itself.
let candidateFiles = cli.modifiedFiles.filter {
    $0.hasSuffix(".swift") && !$0.contains("tools/SnapshotHost/")
}

for file in candidateFiles {
    let (result, _) = ensureFile(file, autoAdd: cli.autoAdd, projectRoot: cli.projectRoot)
    views.append(result)
    if let reason = result.reason,
       reason.hasPrefix("parse_failed_after_preview_add") ||
       reason.hasPrefix("write_failed") ||
       reason.hasPrefix("read_failed") {
        errors.append("\(reason): \(file)")
    }
}

let result = EnsureResult(views: views, errors: errors)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
if let data = try? encoder.encode(result),
   let s = String(data: data, encoding: .utf8) {
    print(s)
}

exit(errors.isEmpty ? 0 : 1)
