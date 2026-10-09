/// Telnet protocol constants (RFC 854 and friends) used by TN3270.
public enum Telnet {
    public static let SE: UInt8 = 240
    public static let NOP: UInt8 = 241
    public static let BREAK: UInt8 = 243
    public static let IP: UInt8 = 244
    public static let AO: UInt8 = 245
    public static let EOR: UInt8 = 239
    public static let SB: UInt8 = 250
    public static let WILL: UInt8 = 251
    public static let WONT: UInt8 = 252
    public static let DO: UInt8 = 253
    public static let DONT: UInt8 = 254
    public static let IAC: UInt8 = 255

    /// Telnet options relevant to TN3270.
    public enum Option {
        public static let binary: UInt8 = 0
        public static let terminalType: UInt8 = 24
        public static let endOfRecord: UInt8 = 25
        public static let tn3270e: UInt8 = 40
    }

    /// TERMINAL-TYPE sub-negotiation codes (RFC 1091).
    public enum TerminalType {
        public static let IS: UInt8 = 0
        public static let SEND: UInt8 = 1
    }

    /// Escapes IAC bytes in a data record (0xFF -> 0xFF 0xFF).
    public static func escape(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + 4)
        for byte in bytes {
            out.append(byte)
            if byte == IAC { out.append(IAC) }
        }
        return out
    }
}

/// TN3270E constants (RFC 2355).
public enum TN3270E {
    public enum Operation {
        public static let associate: UInt8 = 0
        public static let connect: UInt8 = 1
        public static let deviceType: UInt8 = 2
        public static let functions: UInt8 = 3
        public static let `is`: UInt8 = 4
        public static let reason: UInt8 = 5
        public static let reject: UInt8 = 6
        public static let request: UInt8 = 7
        public static let send: UInt8 = 8
    }

    /// Negotiable TN3270E functions.
    public enum Function: UInt8, CaseIterable, Sendable {
        case bindImage = 0
        case dataStreamControl = 1
        case responses = 2
        case scsControlCodes = 3
        case sysreq = 4
    }

    /// TN3270E header data types.
    public enum DataType: UInt8, Sendable {
        case data3270 = 0x00
        case scsData = 0x01
        case response = 0x02
        case bindImage = 0x03
        case unbind = 0x04
        case nvtData = 0x05
        case request = 0x06
        case sscpLUData = 0x07
        case printEOJ = 0x08
    }

    public enum ResponseFlag {
        public static let noResponse: UInt8 = 0x00
        public static let errorResponse: UInt8 = 0x01
        public static let alwaysResponse: UInt8 = 0x02
        public static let positiveResponse: UInt8 = 0x00
        public static let negativeResponse: UInt8 = 0x01
    }

    /// Size of the TN3270E message header.
    public static let headerLength = 5
}
