import Foundation

/// IBM 3278 terminal models and their alternate screen sizes.
public enum TerminalModel: Int, Codable, CaseIterable, Identifiable, Sendable {
    case model2 = 2
    case model3 = 3
    case model4 = 4
    case model5 = 5

    public var id: Int { rawValue }

    public var rows: Int {
        switch self {
        case .model2: return 24
        case .model3: return 32
        case .model4: return 43
        case .model5: return 27
        }
    }

    public var columns: Int { self == .model5 ? 132 : 80 }

    /// Terminal type string sent to the host (extended data stream capable).
    public var terminalType: String { "IBM-3278-\(rawValue)-E" }

    public var displayName: String { "Model \(rawValue) (\(rows)×\(columns))" }
}

/// Minimum TLS protocol version accepted when TLS is enabled.
public enum TLSVersion: String, Codable, CaseIterable, Identifiable, Sendable {
    case tls12 = "TLSv1.2"
    case tls13 = "TLSv1.3"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tls12: return "TLS 1.2"
        case .tls13: return "TLS 1.3"
        }
    }
}

/// User configurable options for connecting to a z/OS TN3270 server.
public struct ConnectionSettings: Codable, Equatable, Sendable {
    /// Host name or IP address of the TN3270 server.
    public var host: String
    /// TCP port (23 for plain telnet, 992 is the conventional TLS port).
    public var port: Int
    /// EBCDIC code page identifier (see `CodePage.all`).
    public var codePageID: String
    /// Terminal model (screen size).
    public var model: TerminalModel
    /// Negotiate TN3270E when offered by the server.
    public var useTN3270E: Bool
    /// Optional LU / device name to request.
    public var luName: String
    /// Wrap the connection in TLS.
    public var useTLS: Bool
    /// Minimum TLS version (TLS 1.3 by default).
    public var minimumTLSVersion: TLSVersion
    /// Validate the server certificate chain and host name.
    public var verifyCertificate: Bool

    public init(host: String = "",
                port: Int = 23,
                codePageID: String = CodePage.default.id,
                model: TerminalModel = .model2,
                useTN3270E: Bool = true,
                luName: String = "",
                useTLS: Bool = false,
                minimumTLSVersion: TLSVersion = .tls13,
                verifyCertificate: Bool = true) {
        self.host = host
        self.port = port
        self.codePageID = codePageID
        self.model = model
        self.useTN3270E = useTN3270E
        self.luName = luName
        self.useTLS = useTLS
        self.minimumTLSVersion = minimumTLSVersion
        self.verifyCertificate = verifyCertificate
    }

    /// The selected code page, falling back to CECP 037.
    public var codePage: CodePage { CodePage.named(codePageID) ?? .default }

    /// Problems that prevent a connection attempt; empty when valid.
    public var validationErrors: [String] {
        var errors: [String] = []
        if host.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Host name or IP address is required.")
        }
        if !(1...65535).contains(port) {
            errors.append("Port must be between 1 and 65535.")
        }
        if CodePage.named(codePageID) == nil {
            errors.append("Unknown EBCDIC code page \(codePageID).")
        }
        if luName.count > 8 || !luName.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "@#$".contains($0)) }) {
            errors.append("LU name must be at most 8 alphanumeric characters.")
        }
        return errors
    }

    public var isValid: Bool { validationErrors.isEmpty }
}
