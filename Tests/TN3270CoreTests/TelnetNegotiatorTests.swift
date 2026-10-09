import XCTest
@testable import TN3270Core

final class TelnetNegotiatorTests: XCTestCase {
    private var sent: [[UInt8]] = []
    private var records: [[UInt8]] = []

    private func makeNegotiator(tn3270e: Bool = true, lu: String? = nil) -> TelnetNegotiator {
        sent = []
        records = []
        let negotiator = TelnetNegotiator(terminalType: "IBM-3278-2-E", allowTN3270E: tn3270e, luName: lu)
        negotiator.send = { [unowned self] in self.sent.append($0) }
        negotiator.onRecord = { [unowned self] in self.records.append($0) }
        return negotiator
    }

    private let IAC = Telnet.IAC
    private let SB = Telnet.SB
    private let SE = Telnet.SE

    func testTN3270ENegotiation() {
        let n = makeNegotiator(lu: "LU01")
        n.receive([IAC, Telnet.DO, Telnet.Option.tn3270e])
        XCTAssertEqual(sent.last, [IAC, Telnet.WILL, Telnet.Option.tn3270e])

        n.receive([IAC, SB, Telnet.Option.tn3270e, TN3270E.Operation.send, TN3270E.Operation.deviceType, IAC, SE])
        let type: [UInt8] = Array("IBM-3278-2-E".utf8)
        let lu: [UInt8] = Array("LU01".utf8)
        var request: [UInt8] = [IAC, SB, 40, 2, 7]
        request += type
        request += [1]
        request += lu
        request += [IAC, SE]
        XCTAssertEqual(sent.last, request)

        var reply: [UInt8] = [IAC, SB, 40, 2, 4]
        reply += type
        reply += [1]
        reply += lu
        reply += [IAC, SE]
        n.receive(reply)
        XCTAssertEqual(n.negotiatedDeviceType, "IBM-3278-2-E")
        XCTAssertEqual(n.connectedLU, "LU01")
        XCTAssertEqual(sent.last, [IAC, SB, 40, 3, 7, 0, 2, 4, IAC, SE])
        XCTAssertEqual(n.mode, .negotiating)

        n.receive([IAC, SB, 40, 3, 4, 0, 2, IAC, SE])
        XCTAssertEqual(n.mode, .tn3270e)
        XCTAssertEqual(n.negotiatedFunctions, [.bindImage, .responses])

        n.receive([0x00, 0x00, 0x00, 0x00, 0x01, 0xF5, IAC, IAC, IAC, Telnet.EOR])
        XCTAssertEqual(records, [[0x00, 0x00, 0x00, 0x00, 0x01, 0xF5, 0xFF]])
    }

    func testFunctionsCounterProposalIsAccepted() {
        let n = makeNegotiator()
        n.receive([IAC, Telnet.DO, 40])
        n.receive([IAC, SB, 40, 3, 7, 2, IAC, SE])
        XCTAssertEqual(sent.last, [IAC, SB, 40, 3, 4, 2, IAC, SE])
        XCTAssertEqual(n.mode, .tn3270e)
    }

    func testFallbackToBasicTN3270() {
        let n = makeNegotiator(tn3270e: false)
        n.receive([IAC, Telnet.DO, 40])
        XCTAssertEqual(sent.last, [IAC, Telnet.WONT, 40])

        n.receive([IAC, Telnet.DO, Telnet.Option.terminalType])
        XCTAssertEqual(sent.last, [IAC, Telnet.WILL, 24])
        n.receive([IAC, SB, 24, Telnet.TerminalType.SEND, IAC, SE])
        var terminalType: [UInt8] = [IAC, SB, 24, 0]
        terminalType += Array("IBM-3278-2-E".utf8)
        terminalType += [IAC, SE]
        XCTAssertEqual(sent.last, terminalType)

        n.receive([IAC, Telnet.DO, 25, IAC, Telnet.WILL, 25, IAC, Telnet.DO, 0, IAC, Telnet.WILL, 0])
        XCTAssertEqual(n.mode, .tn3270)

        n.receive([0xF5, 0xC3, IAC, Telnet.EOR])
        XCTAssertEqual(records, [[0xF5, 0xC3]])
    }

    func testDeviceTypeRejectFallsBack() {
        let n = makeNegotiator()
        n.receive([IAC, Telnet.DO, 40])
        n.receive([IAC, SB, 40, 2, 6, 5, 0x03, IAC, SE])
        XCTAssertEqual(sent.last, [IAC, Telnet.WONT, 40])
        n.receive([IAC, Telnet.DO, 40])
        XCTAssertEqual(sent.last, [IAC, Telnet.WONT, 40])
    }

    func testUnknownOptionsRefused() {
        let n = makeNegotiator()
        n.receive([IAC, Telnet.DO, 31, IAC, Telnet.WILL, 1])
        XCTAssertEqual(sent, [[IAC, Telnet.WONT, 31], [IAC, Telnet.DONT, 1]])
    }

    func testSendRecordEscapesIAC() {
        let n = makeNegotiator()
        n.sendRecord([0x7D, 0xFF, 0x40])
        XCTAssertEqual(sent.last, [0x7D, 0xFF, 0xFF, 0x40, IAC, Telnet.EOR])
    }
}
