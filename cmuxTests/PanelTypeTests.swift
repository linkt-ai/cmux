import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class PanelTypeTests: XCTestCase {
    func testGitGraphCaseExists() {
        let panelType = PanelType.gitGraph
        XCTAssertEqual(panelType.rawValue, "gitGraph")
    }

    func testGitGraphCodableRoundTrip() throws {
        let original = PanelType.gitGraph
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PanelType.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testGitGraphDecodesFromString() throws {
        let json = Data(#""gitGraph""#.utf8)
        let decoded = try JSONDecoder().decode(PanelType.self, from: json)
        XCTAssertEqual(decoded, .gitGraph)
    }

    func testAllCasesExhaustive() {
        let cases: [PanelType] = [.terminal, .browser, .gitGraph]
        XCTAssertEqual(cases.count, 3)
    }
}
