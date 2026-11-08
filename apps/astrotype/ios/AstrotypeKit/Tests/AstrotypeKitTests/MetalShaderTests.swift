import Foundation
import Testing

/// The keyboard's Metal shaders (`Shaders/KeyboardShaders.metal`) are compiled by Xcode,
/// which these tests can't run: this keeps the file and the pipelines `MetalKeyboard`
/// makes from it in step.
@Suite struct MetalShaderTests {
    @Test func theShaderFileHasEveryFunctionThePipelinesUse() throws {
        let ui = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/AstrotypeUI")
        let swift = try String(contentsOf: ui.appendingPathComponent("MetalKeyboard.swift"), encoding: .utf8)
        let metal = try String(contentsOf: ui.appendingPathComponent("Shaders/KeyboardShaders.metal"), encoding: .utf8)
        let used = swift.matches(of: /(vertex|fragment): "(\w+)"/).map { (kind: String($0.1), name: String($0.2)) }
        #expect(used.count == 6, "\(used)")
        for (kind, name) in used {
            // `vertex SkyOut sky_vertex(`
            let declared = try Regex("(^|\\n)\(kind) \\w+ \(name)\\(")
            #expect(metal.contains(declared), "\(kind) \(name) is missing from KeyboardShaders.metal")
        }
    }
}
