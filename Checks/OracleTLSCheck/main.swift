import Foundation
import NIOCore
import NIOPosix
import NIOSSL
import NIOTLS

final class HandshakeCheck: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    let result: EventLoopPromise<Void>
    init(result: EventLoopPromise<Void>) { self.result = result }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? TLSUserEvent, case .handshakeCompleted = event {
            result.succeed(())
        }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        result.fail(error)
        context.close(promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) {
        result.fail(ChannelError.alreadyClosed)
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fatalError("Usage: OracleTLSCheck hostname ewallet.pem additional|explicit")
}
let host = arguments[1]
let certificates = try NIOSSLCertificate.fromPEMFile(arguments[2])
var tls = TLSConfiguration.makeClientConfiguration()
tls.certificateVerification = .fullVerification
if arguments[3] == "explicit" {
    tls.trustRoots = .certificates(certificates)
} else {
    tls.additionalTrustRoots = [.certificates(certificates)]
}
let sslContext = try NIOSSLContext(configuration: tls)
let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
defer { try? group.syncShutdownGracefully() }
let loop = group.next()
let result = loop.makePromise(of: Void.self)
let channel = try ClientBootstrap(group: loop)
    .connectTimeout(.seconds(10))
    .channelInitializer { channel in
        do {
            let handler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
            try channel.pipeline.syncOperations.addHandlers(handler, HandshakeCheck(result: result))
            return channel.eventLoop.makeSucceededFuture(())
        } catch { return channel.eventLoop.makeFailedFuture(error) }
    }
    .connect(host: host, port: 2484).wait()
defer { try? channel.close().wait() }
let timeout = loop.scheduleTask(in: .seconds(10)) { result.fail(ChannelError.connectTimeout(.seconds(10))) }
defer { timeout.cancel() }
do {
    try result.futureResult.wait()
    print("TLS handshake passed with \(arguments[3]) wallet trust and full hostname verification.")
} catch {
    print("TLS handshake failed with \(arguments[3]) wallet trust: \(error)")
    exit(1)
}
