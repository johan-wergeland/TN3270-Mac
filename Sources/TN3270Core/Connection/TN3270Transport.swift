/// Connection state of a transport.
public enum TransportState: Equatable, Sendable {
    case connecting
    case connected
    case disconnected
    case failed(String)
}

/// A byte stream connection to a TN3270 server (TCP, optionally TLS).
public protocol TN3270Transport: AnyObject {
    /// Called with bytes received from the server.
    var onReceive: (([UInt8]) -> Void)? { get set }
    /// Called when the connection state changes.
    var onStateChange: ((TransportState) -> Void)? { get set }

    func connect()
    func send(_ bytes: [UInt8])
    func disconnect()
}
