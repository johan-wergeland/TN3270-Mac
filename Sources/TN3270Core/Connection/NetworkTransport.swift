#if canImport(Network)
import Foundation
import Network
import Security

/// TCP transport built on Network.framework with optional TLS (1.3 by default).
public final class NetworkTransport: TN3270Transport {
    public var onReceive: (([UInt8]) -> Void)?
    public var onStateChange: ((TransportState) -> Void)?

    private let settings: ConnectionSettings
    private let queue: DispatchQueue
    private var connection: NWConnection?

    /// - Parameters:
    ///   - settings: host, port and TLS options.
    ///   - queue: queue on which callbacks are delivered (main by default).
    public init(settings: ConnectionSettings, queue: DispatchQueue = .main) {
        self.settings = settings
        self.queue = queue
    }

    /// Builds the Network.framework parameters for the given settings.
    public static func parameters(for settings: ConnectionSettings, queue: DispatchQueue = .main) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.connectionTimeout = 30

        guard settings.useTLS else {
            return NWParameters(tls: nil, tcp: tcp)
        }

        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        switch settings.minimumTLSVersion {
        case .tls12:
            sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        case .tls13:
            sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        }
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv13)
        if !settings.verifyCertificate {
            // Accept self-signed / private CA certificates (e.g. internal z/OS hosts).
            sec_protocol_options_set_verify_block(options, { _, _, complete in
                complete(true)
            }, queue)
        }
        return NWParameters(tls: tls, tcp: tcp)
    }

    public func connect() {
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: settings.port)) else {
            onStateChange?(.failed("Invalid port \(settings.port)"))
            return
        }
        let host = NWEndpoint.Host(settings.host.trimmingCharacters(in: .whitespaces))
        let connection = NWConnection(host: host, port: port,
                                      using: Self.parameters(for: settings, queue: queue))
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .preparing, .setup:
                self.onStateChange?(.connecting)
            case .ready:
                self.onStateChange?(.connected)
                self.receiveNext()
            case .waiting(let error):
                self.onStateChange?(.failed(error.localizedDescription))
                connection.cancel()
            case .failed(let error):
                self.onStateChange?(.failed(error.localizedDescription))
                self.connection = nil
            case .cancelled:
                self.onStateChange?(.disconnected)
                self.connection = nil
            @unknown default:
                break
            }
        }
        connection.start(queue: queue)
    }

    public func send(_ bytes: [UInt8]) {
        guard let connection else { return }
        connection.send(content: Data(bytes), completion: .contentProcessed { [weak self] error in
            if let error {
                self?.onStateChange?(.failed(error.localizedDescription))
            }
        })
    }

    public func disconnect() {
        connection?.cancel()
    }

    private func receiveNext() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.onReceive?([UInt8](data))
            }
            if let error {
                self.onStateChange?(.failed(error.localizedDescription))
                connection.cancel()
            } else if isComplete {
                connection.cancel()
            } else {
                self.receiveNext()
            }
        }
    }
}
#endif
