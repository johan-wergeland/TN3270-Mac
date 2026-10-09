/// The negotiated mode of a telnet connection to a TN3270 server.
public enum TelnetMode: Equatable, Sendable {
    /// Option negotiation still in progress.
    case negotiating
    /// Plain telnet (NVT) - the server didn't agree to 3270 mode.
    case nvt
    /// Traditional TN3270 (RFC 1576): BINARY + EOR + TERMINAL-TYPE.
    case tn3270
    /// TN3270E (RFC 2355).
    case tn3270e
}

/// Implements the client side of telnet option negotiation for TN3270 and
/// TN3270E and splits the inbound byte stream into 3270 records.
///
/// The negotiator is transport agnostic: feed it bytes with `receive(_:)`
/// and it calls `send` with bytes that must be written to the server.
public final class TelnetNegotiator {
    /// Called with raw bytes that should be written to the network.
    public var send: ([UInt8]) -> Void = { _ in }
    /// Called with every complete inbound record (delimited by IAC EOR).
    /// In TN3270E mode the 5-byte TN3270E header is still present.
    public var onRecord: ([UInt8]) -> Void = { _ in }
    /// Called with data received while in NVT (line) mode.
    public var onNVTData: ([UInt8]) -> Void = { _ in }
    /// Called whenever the negotiated mode changes.
    public var onModeChange: (TelnetMode) -> Void = { _ in }

    /// The terminal type sent to the host, e.g. "IBM-3278-2-E".
    public var terminalType: String
    /// Whether TN3270E should be negotiated if the server offers it.
    public var allowTN3270E: Bool
    /// Optional LU name to request (TN3270E CONNECT / basic TN3270 terminal type suffix).
    public var luName: String?
    /// The TN3270E functions this client is prepared to support.
    public var supportedFunctions: Set<TN3270E.Function> = [.bindImage, .responses, .sysreq]

    public private(set) var mode: TelnetMode = .negotiating {
        didSet { if mode != oldValue { onModeChange(mode) } }
    }
    /// Device type confirmed by the server in TN3270E mode.
    public private(set) var negotiatedDeviceType: String?
    /// LU name assigned by the server in TN3270E mode.
    public private(set) var connectedLU: String?
    /// Functions agreed with the server in TN3270E mode.
    public private(set) var negotiatedFunctions: Set<TN3270E.Function> = []

    private enum ParseState {
        case data, iac, will, wont, `do`, dont, sb, sbIAC
    }

    private var state: ParseState = .data
    private var record: [UInt8] = []
    private var subnegotiation: [UInt8] = []
    private var localOptions: Set<UInt8> = []   // options we WILL perform
    private var remoteOptions: Set<UInt8> = []  // options the server WILL perform
    private var tn3270eRefused = false

    public init(terminalType: String, allowTN3270E: Bool = true, luName: String? = nil) {
        self.terminalType = terminalType
        self.allowTN3270E = allowTN3270E
        self.luName = luName
    }

    /// Resets the negotiator for a new connection.
    public func reset() {
        state = .data
        record = []
        subnegotiation = []
        localOptions = []
        remoteOptions = []
        tn3270eRefused = false
        negotiatedDeviceType = nil
        connectedLU = nil
        negotiatedFunctions = []
        negotiatedFunctionsComplete = false
        mode = .negotiating
    }

    // MARK: - Inbound

    /// Processes bytes received from the server.
    public func receive<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
        var nvt: [UInt8] = []
        for byte in bytes {
            switch state {
            case .data:
                if byte == Telnet.IAC {
                    state = .iac
                } else if mode == .tn3270 || mode == .tn3270e {
                    record.append(byte)
                } else {
                    nvt.append(byte)
                }
            case .iac:
                state = .data
                switch byte {
                case Telnet.IAC:
                    if mode == .tn3270 || mode == .tn3270e { record.append(byte) } else { nvt.append(byte) }
                case Telnet.EOR:
                    let complete = record
                    record = []
                    if !complete.isEmpty { onRecord(complete) }
                case Telnet.WILL: state = .will
                case Telnet.WONT: state = .wont
                case Telnet.DO: state = .do
                case Telnet.DONT: state = .dont
                case Telnet.SB:
                    state = .sb
                    subnegotiation = []
                default:
                    break // NOP, GA, etc.
                }
            case .will:
                state = .data
                handleWill(byte)
            case .wont:
                state = .data
                handleWont(byte)
            case .do:
                state = .data
                handleDo(byte)
            case .dont:
                state = .data
                handleDont(byte)
            case .sb:
                if byte == Telnet.IAC { state = .sbIAC } else { subnegotiation.append(byte) }
            case .sbIAC:
                if byte == Telnet.SE {
                    state = .data
                    handleSubnegotiation(subnegotiation)
                    subnegotiation = []
                } else {
                    subnegotiation.append(byte)
                    state = .sb
                }
            }
        }
        if !nvt.isEmpty { onNVTData(nvt) }
    }

    // MARK: - Outbound

    /// Sends a 3270 record, escaping IAC bytes and appending IAC EOR.
    public func sendRecord(_ data: [UInt8]) {
        send(Telnet.escape(data) + [Telnet.IAC, Telnet.EOR])
    }

    /// Sends a telnet command such as IP or AO.
    public func sendCommand(_ command: UInt8) {
        send([Telnet.IAC, command])
    }

    // MARK: - Option negotiation

    private func handleDo(_ option: UInt8) {
        switch option {
        case Telnet.Option.tn3270e:
            if allowTN3270E && !tn3270eRefused {
                enableLocal(option)
            } else {
                refuseLocal(option)
            }
        case Telnet.Option.terminalType, Telnet.Option.binary, Telnet.Option.endOfRecord:
            enableLocal(option)
        default:
            refuseLocal(option)
        }
        updateMode()
    }

    private func handleDont(_ option: UInt8) {
        if localOptions.contains(option) {
            localOptions.remove(option)
            sendNegotiation(Telnet.WONT, option)
        }
        if option == Telnet.Option.tn3270e {
            tn3270eRefused = true
            negotiatedFunctions = []
            negotiatedDeviceType = nil
            negotiatedFunctionsComplete = false
        }
        updateMode()
    }

    private func handleWill(_ option: UInt8) {
        switch option {
        case Telnet.Option.binary, Telnet.Option.endOfRecord:
            if !remoteOptions.contains(option) {
                remoteOptions.insert(option)
                sendNegotiation(Telnet.DO, option)
            }
        default:
            sendNegotiation(Telnet.DONT, option)
        }
        updateMode()
    }

    private func handleWont(_ option: UInt8) {
        if remoteOptions.contains(option) {
            remoteOptions.remove(option)
            sendNegotiation(Telnet.DONT, option)
        }
        updateMode()
    }

    private func enableLocal(_ option: UInt8) {
        if !localOptions.contains(option) {
            localOptions.insert(option)
            sendNegotiation(Telnet.WILL, option)
        }
    }

    private func refuseLocal(_ option: UInt8) {
        localOptions.remove(option)
        sendNegotiation(Telnet.WONT, option)
    }

    private func sendNegotiation(_ verb: UInt8, _ option: UInt8) {
        send([Telnet.IAC, verb, option])
    }

    private func sendSubnegotiation(_ payload: [UInt8]) {
        send([Telnet.IAC, Telnet.SB] + Telnet.escape(payload) + [Telnet.IAC, Telnet.SE])
    }

    private func updateMode() {
        if localOptions.contains(Telnet.Option.tn3270e) {
            mode = negotiatedFunctionsComplete ? .tn3270e : .negotiating
            return
        }
        let binary = localOptions.contains(Telnet.Option.binary) && remoteOptions.contains(Telnet.Option.binary)
        let eor = localOptions.contains(Telnet.Option.endOfRecord) && remoteOptions.contains(Telnet.Option.endOfRecord)
        if binary && eor {
            mode = .tn3270
        } else if mode == .tn3270 || mode == .tn3270e {
            mode = .nvt
        }
    }

    private var negotiatedFunctionsComplete = false

    // MARK: - Sub-negotiation

    private func handleSubnegotiation(_ data: [UInt8]) {
        guard let option = data.first else { return }
        let body = Array(data.dropFirst())
        switch option {
        case Telnet.Option.terminalType:
            if body.first == Telnet.TerminalType.SEND {
                var name = terminalType
                if let lu = luName, !lu.isEmpty { name += "@" + lu }
                sendSubnegotiation([Telnet.Option.terminalType, Telnet.TerminalType.IS] + Array(name.utf8))
            }
        case Telnet.Option.tn3270e:
            handleTN3270ESubnegotiation(body)
        default:
            break
        }
    }

    private func handleTN3270ESubnegotiation(_ body: [UInt8]) {
        guard body.count >= 2 else { return }
        let operation = body[0]
        let verb = body[1]
        let rest = Array(body.dropFirst(2))

        switch (operation, verb) {
        case (TN3270E.Operation.send, TN3270E.Operation.deviceType):
            sendDeviceTypeRequest()

        case (TN3270E.Operation.deviceType, TN3270E.Operation.is):
            // DEVICE-TYPE IS <device-type> CONNECT <device-name>
            if let connectIndex = rest.firstIndex(of: TN3270E.Operation.connect) {
                negotiatedDeviceType = String(decoding: rest[..<connectIndex], as: UTF8.self)
                connectedLU = String(decoding: rest[(connectIndex + 1)...], as: UTF8.self)
            } else {
                negotiatedDeviceType = String(decoding: rest, as: UTF8.self)
            }
            sendFunctions(TN3270E.Operation.request, supportedFunctions)

        case (TN3270E.Operation.deviceType, TN3270E.Operation.reject):
            // Fall back to traditional TN3270.
            tn3270eRefused = true
            localOptions.remove(Telnet.Option.tn3270e)
            sendNegotiation(Telnet.WONT, Telnet.Option.tn3270e)
            updateMode()

        case (TN3270E.Operation.functions, TN3270E.Operation.request):
            let requested = Set(rest.compactMap(TN3270E.Function.init(rawValue:)))
            let acceptable = requested.intersection(supportedFunctions)
            if acceptable == requested && rest.count == requested.count {
                negotiatedFunctions = acceptable
                sendFunctions(TN3270E.Operation.is, acceptable)
                negotiatedFunctionsComplete = true
                updateMode()
            } else {
                sendFunctions(TN3270E.Operation.request, acceptable)
            }

        case (TN3270E.Operation.functions, TN3270E.Operation.is):
            negotiatedFunctions = Set(rest.compactMap(TN3270E.Function.init(rawValue:)))
            negotiatedFunctionsComplete = true
            updateMode()

        default:
            break
        }
    }

    private func sendDeviceTypeRequest() {
        var payload: [UInt8] = [Telnet.Option.tn3270e, TN3270E.Operation.deviceType, TN3270E.Operation.request]
        payload += Array(terminalType.utf8)
        if let lu = luName, !lu.isEmpty {
            payload.append(TN3270E.Operation.connect)
            payload += Array(lu.utf8)
        }
        sendSubnegotiation(payload)
    }

    private func sendFunctions(_ verb: UInt8, _ functions: Set<TN3270E.Function>) {
        let codes = functions.map(\.rawValue).sorted()
        sendSubnegotiation([Telnet.Option.tn3270e, TN3270E.Operation.functions, verb] + codes)
    }
}
