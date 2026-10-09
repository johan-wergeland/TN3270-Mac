import XCTest
@testable import TN3270Core

final class CodePageTests: XCTestCase {
    func testAllCodePagesHaveFullTables() {
        XCTAssertGreaterThanOrEqual(CodePage.all.count, 19)
        for page in CodePage.all {
            XCTAssertEqual(page.character(for: 0x40), " ", page.id)
            XCTAssertEqual(page.character(for: 0xC1), "A", page.id)
            XCTAssertEqual(page.character(for: 0xF0), "0", page.id)
        }
    }

    func testRoundTrip037() {
        let page = CodePage.named("037")!
        let text = "HELLO, z/OS 3270!"
        let bytes = page.encode(text)
        XCTAssertEqual(bytes.first, 0xC8)
        XCTAssertEqual(page.decode(bytes), text)
    }

    func testBracketsDifferBetween037And1047() {
        XCTAssertEqual(CodePage.named("037")!.ebcdic(for: "["), 0xBA)
        XCTAssertEqual(CodePage.named("1047")!.ebcdic(for: "["), 0xAD)
    }

    func testEuroCodePage() {
        XCTAssertEqual(CodePage.named("1140")!.character(for: 0x9F), "€")
        XCTAssertEqual(CodePage.named("037")!.ebcdic(for: "€"), nil)
    }

    func testNamedLookupAcceptsPrefixes() {
        XCTAssertEqual(CodePage.named("CP1047")?.id, "1047")
        XCTAssertEqual(CodePage.named("IBM-273")?.id, "273")
        XCTAssertEqual(CodePage.named("37")?.id, "037")
        XCTAssertNil(CodePage.named("9999"))
    }
}

final class AddressTests: XCTestCase {
    func testTwelveBitAddressRoundTrip() {
        for address in [0, 1, 79, 80, 1919, 3563] {
            let encoded = DS.encodeAddress(address, bufferSize: 1920)
            XCTAssertEqual(DS.decodeAddress(encoded[0], encoded[1]), address)
        }
        XCTAssertEqual(DS.encodeAddress(80, bufferSize: 1920), [0xC1, 0x50])
    }

    func testFourteenBitAddress() {
        XCTAssertEqual(DS.decodeAddress(0x10, 0x00), 4096)
        XCTAssertEqual(DS.encodeAddress(5000, bufferSize: 5000 + 1), [0x13, 0x88])
    }
}
