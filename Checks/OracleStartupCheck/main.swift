import Foundation
import OracleNIO
import NIOSSL

@main
struct StartupCheck {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 5 else { fatalError("Usage: OracleStartupCheck host pem service timeout") }
        let certificates = try NIOSSLCertificate.fromPEMFile(args[2])
        var tls = TLSConfiguration.makeClientConfiguration()
        if ProcessInfo.processInfo.environment["CHECK_MTLS"] == "1" {
            tls = try TLSConfiguration.makeOracleWalletConfiguration(pemFile: args[2], pemPassword: "")
        }
        tls.trustRoots = .certificates(certificates)
        tls.certificateVerification = .fullVerification
        if ProcessInfo.processInfo.environment["CHECK_TLS12"] == "1" { tls.maximumTLSVersion = .tlsv12 }
        var config = OracleConnection.Configuration(host: args[1], port: 2484,
            service: .serviceName(args[3]), username: "", password: "",
            tls: .require(try NIOSSLContext(configuration: tls)))
        config.options.connectTimeout = .seconds(Int64(args[4]) ?? 15)
        if let address = ProcessInfo.processInfo.environment["CHECK_IP"] {
            config.options.tlsServerName = args[1]
            config.host = address
        }
        let start = ContinuousClock.now
        do {
            let connection = try await OracleConnection.connect(configuration: config, id: 0)
            try await connection.close()
            print("Startup completed")
        } catch let error as OracleSQLError {
            print("Elapsed: \(start.duration(to: .now)); code: \(error.code); server: \(error.serverInfo?.message ?? "none"); underlying: \(String(describing: error.underlying))")
        }
    }
}
