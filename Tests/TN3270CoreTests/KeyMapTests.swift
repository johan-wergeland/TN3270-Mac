import XCTest
@testable import TN3270Core

final class KeyMapTests: XCTestCase {
    func testDefaultBindings() {
        let map = KeyMap.default
        XCTAssertEqual(map.action(for: KeyStroke("Return")), .enter)
        XCTAssertEqual(map.action(for: KeyStroke("F3")), .pf3)
        XCTAssertEqual(map.action(for: KeyStroke("F3", .shift)), .pf15)
        XCTAssertEqual(map.action(for: KeyStroke("Tab", .shift)), .backtab)
        XCTAssertEqual(map.action(for: KeyStroke("R", .control)), .reset)
        XCTAssertNil(map.action(for: KeyStroke("a")))
    }

    func testRebindReplacesExistingStroke() {
        var map = KeyMap.default
        let count = map.bindings.count
        map.bind(KeyStroke("Return"), to: .newline)
        XCTAssertEqual(map.action(for: KeyStroke("Return")), .newline)
        XCTAssertEqual(map.bindings.count, count)
        map.unbind(KeyStroke("Return"))
        XCTAssertNil(map.action(for: KeyStroke("Return")))
        XCTAssertTrue(map.strokes(for: .enter).contains(KeyStroke("Enter")))
    }

    func testCodableRoundTrip() throws {
        var map = KeyMap.default
        map.bind(KeyStroke("p", [.control, .option]), to: .pa2)
        let data = try JSONEncoder().encode(map)
        XCTAssertEqual(try JSONDecoder().decode(KeyMap.self, from: data), map)
    }

    func testDisplayName() {
        XCTAssertEqual(KeyStroke("F1", [.shift, .control]).displayName, "⌃⇧F1")
        XCTAssertEqual(KeyStroke("c", .control).displayName, "⌃C")
    }
}

final class ConnectionSettingsTests: XCTestCase {
    func testDefaultsUseTLS13() {
        let settings = ConnectionSettings()
        XCTAssertEqual(settings.minimumTLSVersion, .tls13)
        XCTAssertEqual(settings.codePage.id, "037")
        XCTAssertFalse(settings.isValid) // host required
    }

    func testValidation() {
        var settings = ConnectionSettings(host: "10.1.2.3", port: 992, codePageID: "1047", useTLS: true)
        XCTAssertTrue(settings.isValid, settings.validationErrors.joined())
        settings.port = 70000
        settings.luName = "TOO-LONG-NAME"
        XCTAssertEqual(settings.validationErrors.count, 2)
    }

    func testCodable() throws {
        let settings = ConnectionSettings(host: "zos", port: 2023, codePageID: "273", model: .model5, luName: "LU1")
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(ConnectionSettings.self, from: data), settings)
        XCTAssertEqual(settings.model.terminalType, "IBM-3278-5-E")
    }
}
