#if canImport(Network)
import Network
import Security
import XCTest
@testable import TN3270Core

final class NetworkTransportTests: XCTestCase {
    func testBadCertificateFormatExplainsParsingFailure() {
        let description = NetworkTransport.failureDescription(for: .tls(errSSLBadCert))

        XCTAssertTrue(description.contains("-9808"))
        XCTAssertTrue(description.contains("could not parse the server certificate"))
        XCTAssertTrue(description.contains("host and port use direct TLS"))
        XCTAssertTrue(description.contains("Disabling certificate verification does not bypass certificate parsing"))
    }

    func testOtherTLSErrorsKeepOriginalDescription() {
        let error = NWError.tls(errSSLUnknownRootCert)

        XCTAssertEqual(NetworkTransport.failureDescription(for: error), error.localizedDescription)
    }

    func testNonTLSErrorsKeepOriginalDescription() {
        let error = NWError.posix(.ECONNREFUSED)

        XCTAssertEqual(NetworkTransport.failureDescription(for: error), error.localizedDescription)
    }
}
#endif