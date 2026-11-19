import XCTest
@testable import TN3270Core

final class DataStreamTests: XCTestCase {
    private let cp = CodePage.default

    /// EW, WCC(restore+reset MDT), protected label, unprotected input field
    /// with the cursor, then an autoskip field at address 20.
    private func loginScreen() -> [UInt8] {
        var record: [UInt8] = [0xF5, 0xC3, 0x11, 0x40, 0x40, 0x1D, 0xE8]
        record += cp.encode("USERID")
        record += [0x1D, 0x40, 0x13]
        record += [0x11] + DS.encodeAddress(20, bufferSize: 1920) + [0x1D, 0xF0]
        return record
    }

    func testEraseWriteBuildsFields() {
        let processor = DataStreamProcessor()
        let result = processor.process(loginScreen())
        XCTAssertTrue(result.keyboardRestore)
        XCTAssertEqual(processor.screen.cursor, 8)
        XCTAssertTrue(processor.screen.isFormatted)
        XCTAssertTrue(processor.screen[0].isFieldAttribute)
        XCTAssertTrue(processor.screen.isProtected(3))
        XCTAssertFalse(processor.screen.isProtected(8))
        XCTAssertTrue(processor.screen.isProtected(25))
        XCTAssertEqual(processor.screen.text(row: 0, codePage: cp).prefix(8), " USERID ")
        XCTAssertEqual(processor.screen.appearance(at: 3).foreground, .white)
        XCTAssertEqual(processor.screen.appearance(at: 8).foreground, .green)
    }

    func testRepeatToAddressAndEraseUnprotected() {
        let processor = DataStreamProcessor()
        processor.process([0xF5, 0xC3, 0x3C] + DS.encodeAddress(10, bufferSize: 1920) + [0xC1])
        XCTAssertEqual(processor.screen.text(row: 0, codePage: cp).prefix(11), "AAAAAAAAAA ")

        processor.process(loginScreen())
        processor.process([0xF1, 0xC3, 0x11] + DS.encodeAddress(8, bufferSize: 1920) + cp.encode("ABC"))
        XCTAssertEqual(processor.screen[8].byte, 0xC1)
        processor.process([0xF1, 0xC3, 0x11, 0x40, 0x40, 0x12] + DS.encodeAddress(30, bufferSize: 1920))
        XCTAssertEqual(processor.screen[8].byte, 0x00)
        XCTAssertEqual(processor.screen[1].byte, 0xE4) // protected "U" untouched
    }

    func testExtendedAttributes() {
        let processor = DataStreamProcessor()
        // SFE with field attribute (protected) and red foreground, then SA reverse video text.
        processor.process([0xF5, 0xC3, 0x29, 0x02, 0xC0, 0x60, 0x42, 0xF2, 0xC1, 0x28, 0x41, 0xF2, 0xC2])
        XCTAssertEqual(processor.screen.appearance(at: 1).foreground, .red)
        XCTAssertFalse(processor.screen.appearance(at: 1).reverse)
        XCTAssertTrue(processor.screen.appearance(at: 2).reverse)
        XCTAssertEqual(processor.screen.appearances().count, 1920)
    }

    func testEraseWriteAlternateUsesModelSize() {
        let processor = DataStreamProcessor(model: .model5)
        processor.process([0x7E, 0xC3])
        XCTAssertEqual(processor.screen.rows, 27)
        XCTAssertEqual(processor.screen.columns, 132)
        processor.process([0xF5, 0xC3])
        XCTAssertEqual(processor.screen.rows, 24)
    }

    func testReadPartitionQueryReply() {
        let processor = DataStreamProcessor(model: .model4)
        let result = processor.process([0xF3, 0x00, 0x05, 0x01, 0xFF, 0x02])
        XCTAssertEqual(result.replies.count, 1)
        let reply = result.replies[0]
        XCTAssertEqual(reply.first, DS.AID.structuredField)
        // Walk the structured fields and check their lengths are consistent.
        var index = 1
        var codes: [UInt8] = []
        while index < reply.count {
            let length = Int(reply[index]) << 8 | Int(reply[index + 1])
            XCTAssertEqual(reply[index + 2], 0x81)
            codes.append(reply[index + 3])
            if reply[index + 3] == DS.QueryCode.usableArea {
                XCTAssertEqual(Array(reply[(index + 6)...(index + 9)]), [0x00, 80, 0x00, 43])
            }
            index += length
        }
        XCTAssertEqual(index, reply.count)
        XCTAssertEqual(codes, [0x80, 0x81, 0x86, 0x87, 0x88, 0xA6])
    }

    func testReadBuffer() {
        let processor = DataStreamProcessor()
        processor.process(loginScreen())
        let result = processor.process([0xF2])
        XCTAssertEqual(result.replies.first?.prefix(5), [0x60, 0x40, 0xC8, 0x1D, 0xE8])
        XCTAssertEqual(result.replies.first?.count, 3 + 1920 + 3)
    }

    func testUnknownCommandIsRejected() {
        XCTAssertTrue(DataStreamProcessor().process([0x99]).commandRejected)
    }
}

final class SessionTests: XCTestCase {
    private var sent: [UInt8] = []
    private var alarms = 0

    private func connectedSession(tn3270e: Bool = false) -> TN3270Session {
        sent = []
        alarms = 0
        let session = TN3270Session(settings: ConnectionSettings(host: "zos.example.com", useTN3270E: tn3270e))
        session.send = { [unowned self] in self.sent += $0 }
        session.onAlarm = { [unowned self] in self.alarms += 1 }
        session.resetForConnection()
        let IAC = Telnet.IAC
        if tn3270e {
            session.receive([IAC, Telnet.DO, 40])
            session.receive([IAC, Telnet.SB, 40, 8, 2, IAC, Telnet.SE])
            session.receive([IAC, Telnet.SB, 40, 2, 4] + Array("IBM-3278-2-E".utf8) + [1] + Array("TCP00001".utf8) + [IAC, Telnet.SE])
            session.receive([IAC, Telnet.SB, 40, 3, 4, 0, 2, 4, IAC, Telnet.SE])
        } else {
            session.receive([IAC, Telnet.DO, 24, IAC, Telnet.DO, 25, IAC, Telnet.WILL, 25, IAC, Telnet.DO, 0, IAC, Telnet.WILL, 0])
        }
        sent = []
        return session
    }

    private func loginScreen() -> [UInt8] {
        var record: [UInt8] = [0xF5, 0xC3, 0x11, 0x40, 0x40, 0x1D, 0xE8]
        record += CodePage.default.encode("USERID")
        record += [0x1D, 0x40, 0x13]
        record += [0x11] + DS.encodeAddress(20, bufferSize: 1920) + [0x1D, 0xF0]
        return record
    }

    func testTypingAndEnterSendsReadModified() {
        let session = connectedSession()
        XCTAssertEqual(session.state, .connected(.tn3270))
        session.receive(loginScreen() + [Telnet.IAC, Telnet.EOR])
        session.type("ibmuser")
        XCTAssertEqual(session.screen.cursor, 15)
        XCTAssertNotEqual(session.screen[7].byte & DS.FieldAttribute.modified, 0)

        session.perform(.enter)
        let expected: [UInt8] = [0x7D] + DS.encodeAddress(15, bufferSize: 1920)
            + [0x11] + DS.encodeAddress(8, bufferSize: 1920)
            + CodePage.default.encode("ibmuser") + [Telnet.IAC, Telnet.EOR]
        XCTAssertEqual(sent, expected)
        XCTAssertTrue(session.keyboardLocked)
        XCTAssertTrue(session.statusText.contains("X SYSTEM"))

        session.type("x")
        XCTAssertEqual(alarms, 1)
        session.perform(.reset)
        XCTAssertFalse(session.keyboardLocked)
    }

    func testProtectedFieldRejectsInputAndAutoskip() {
        let session = connectedSession()
        session.receive(loginScreen() + [Telnet.IAC, Telnet.EOR])
        session.moveCursor(to: 2)
        session.type("A")
        XCTAssertEqual(alarms, 1)
        XCTAssertEqual(session.screen[2].byte, CodePage.default.ebcdic(for: "S"))

        session.perform(.home)
        XCTAssertEqual(session.screen.cursor, 8)
        session.type("123456789012")
        // Autoskip field at 20 sends the cursor back to the only input field.
        XCTAssertEqual(session.screen.cursor, 8)
    }

    func testFieldEditing() {
        let session = connectedSession()
        session.receive(loginScreen() + [Telnet.IAC, Telnet.EOR])
        session.type("ABCD")
        session.moveCursor(to: 9)
        session.perform(.delete)
        XCTAssertEqual(CodePage.default.decode([session.screen[8].byte, session.screen[9].byte, session.screen[10].byte]), "ACD")
        session.perform(.insert)
        session.type("B")
        XCTAssertEqual(CodePage.default.decode((8...11).map { session.screen[$0].byte }), "ABCD")
        session.moveCursor(to: 10)
        session.perform(.eraseEOF)
        XCTAssertEqual(session.screen[10].byte, 0)
        XCTAssertEqual(session.screen[9].byte, CodePage.default.ebcdic(for: "B"))
        session.perform(.backtab)
        XCTAssertEqual(session.screen.cursor, 8)
        session.perform(.tab)
        XCTAssertEqual(session.screen.cursor, 8)
    }

    func testNewlineIncludesEditableFieldAttributeAtStartOfNextRow() {
        for nextRow in [1, 0] {
            let session = connectedSession()
            let columns = session.screen.columns
            let start = nextRow * columns
            var record: [UInt8] = [0xF5, 0xC3, 0x1D, 0x60]
            for address in [start, start + 10] {
                record += [0x11] + DS.encodeAddress(address, bufferSize: session.screen.size) + [0x1D, 0x40]
            }
            session.receive(record + [Telnet.IAC, Telnet.EOR])
            session.moveCursor(to: session.screen.wrap(start - columns + 40))
            let cells = session.screen.cells

            session.perform(.newline)

            XCTAssertEqual(session.screen.cursor, start + 1)
            XCTAssertEqual(session.screen.cells, cells)
            XCTAssertTrue(sent.isEmpty)
            XCTAssertEqual(alarms, 0)
        }
    }

    func testNewlineFindsFirstEditablePositionPastProtectedAndEmptyFields() {
        let session = connectedSession()
        let columns = session.screen.columns
        var record: [UInt8] = [0xF5, 0xC3, 0x1D, 0x60]
        let fields: [(Int, UInt8)] = [
            (columns, 0x60), (columns + 5, 0x40), (columns + 6, 0x40), (columns + 12, 0x40),
        ]
        for (address, attribute) in fields {
            record += [0x11] + DS.encodeAddress(address, bufferSize: session.screen.size) + [0x1D, attribute]
        }
        session.receive(record + [Telnet.IAC, Telnet.EOR])
        session.moveCursor(to: 40)

        session.perform(.newline)

        XCTAssertEqual(session.screen.cursor, columns + 7)
    }

    func testNewlineUsesColumnZeroWhenAlreadyEditable() {
        for formatted in [false, true] {
            let session = connectedSession()
            var record: [UInt8] = [0xF5, 0xC3]
            if formatted { record += [0x1D, 0x40] }
            session.receive(record + [Telnet.IAC, Telnet.EOR])
            session.moveCursor(to: 40)

            session.perform(.newline)

            XCTAssertEqual(session.screen.cursor, session.screen.columns)
        }
    }

    func testClearSendsShortRead() {
        let session = connectedSession()
        session.receive(loginScreen() + [Telnet.IAC, Telnet.EOR])
        session.perform(.clear)
        XCTAssertEqual(sent, [DS.AID.clear, Telnet.IAC, Telnet.EOR])
        XCTAssertFalse(session.screen.isFormatted)
    }

    func testPFKeys() {
        let session = connectedSession()
        session.receive(loginScreen() + [Telnet.IAC, Telnet.EOR])
        session.perform(.pf3)
        XCTAssertEqual(sent.first, 0xF3)
        session.perform(.reset)
        sent = []
        session.perform(.pf24)
        XCTAssertEqual(sent.first, 0x4C)
    }

    func testTN3270EDataAndResponses() {
        let session = connectedSession(tn3270e: true)
        XCTAssertEqual(session.state, .connected(.tn3270e))
        XCTAssertEqual(session.negotiator.connectedLU, "TCP00001")

        // 3270-DATA, ALWAYS-RESPONSE, sequence 0x0007.
        session.receive([0x00, 0x00, 0x02, 0x00, 0x07] + loginScreen() + [Telnet.IAC, Telnet.EOR])
        XCTAssertEqual(sent, [0x02, 0x00, 0x00, 0x00, 0x07, 0x00, Telnet.IAC, Telnet.EOR])
        XCTAssertTrue(session.screen.isFormatted)

        sent = []
        session.perform(.pa1)
        XCTAssertEqual(sent, [0x00, 0x00, 0x00, 0x00, 0x00, DS.AID.pa1, Telnet.IAC, Telnet.EOR])

        sent = []
        session.perform(.attn)
        XCTAssertEqual(sent, [Telnet.IAC, Telnet.IP])

        sent = []
        session.perform(.sysreq)
        XCTAssertEqual(sent, [Telnet.IAC, Telnet.AO])
    }

    func testTN3270EQueryReplyHasHeader() {
        let session = connectedSession(tn3270e: true)
        session.receive([0x00, 0x00, 0x00, 0x00, 0x00, 0xF3, 0x00, 0x05, 0x01, 0xFF, 0xFF, 0x02, Telnet.IAC, Telnet.EOR])
        XCTAssertEqual(Array(sent.prefix(6)), [0x00, 0x00, 0x00, 0x00, 0x00, 0x88])
    }

    func testNumericFieldRejectsLetters() {
        let session = connectedSession()
        // Unprotected numeric field (attribute 0x50) at address 0.
        session.receive([0xF5, 0xC3, 0x1D, 0x50, 0x13, Telnet.IAC, Telnet.EOR])
        session.type("1A")
        XCTAssertEqual(session.screen[1].byte, 0xF1)
        XCTAssertEqual(session.screen[2].byte, 0x00)
        XCTAssertEqual(alarms, 1)
    }
}
