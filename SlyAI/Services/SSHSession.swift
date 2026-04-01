import Foundation
import NIOCore
import NIOPosix
import NIOSSH

@MainActor
class SSHSession: ObservableObject {
    let host: SSHHost
    @Published var isConnected = false
    @Published var outputBuffer: String = ""

    private var group: EventLoopGroup?
    private var channel: Channel?

    init(host: SSHHost) {
        self.host = host
    }

    func connect() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                let clientConfig: SSHClientConfiguration

                switch self.host.authMethod {
                case .password(let password):
                    clientConfig = SSHClientConfiguration(
                        userAuthDelegate: PasswordAuthDelegate(
                            username: self.host.username,
                            password: password
                        ),
                        serverAuthDelegate: AcceptAllHostKeysDelegate()
                    )
                case .privateKey(let keyPath):
                    clientConfig = SSHClientConfiguration(
                        userAuthDelegate: PrivateKeyAuthDelegate(
                            username: self.host.username,
                            keyPath: keyPath
                        ),
                        serverAuthDelegate: AcceptAllHostKeysDelegate()
                    )
                }

                return channel.pipeline.addHandlers([
                    NIOSSHHandler(
                        role: .client(clientConfig),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                ])
            }

        log("Connecting to \(host.hostname):\(host.port)...")

        let channel = try await bootstrap.connect(
            host: host.hostname,
            port: host.port
        ).get()

        self.channel = channel
        self.isConnected = true
        log("SSH channel established")
    }

    func execute(_ command: String) async throws -> String {
        guard isConnected, let parentChannel = channel else {
            throw SSHError.notConnected
        }

        log("Executing: \(command)")

        let result: String = try await withCheckedThrowingContinuation { continuation in
            let dataHandler = ExecDataHandler(command: command, continuation: continuation)

            // Get the SSH handler and create a child channel for exec
            parentChannel.pipeline.handler(type: NIOSSHHandler.self).whenComplete { handlerResult in
                switch handlerResult {
                case .success(let sshHandler):
                    let childPromise = parentChannel.eventLoop.makePromise(of: Channel.self)
                    sshHandler.createChannel(childPromise) { childChannel, channelType in
                        childChannel.pipeline.addHandlers([dataHandler])
                    }
                    childPromise.futureResult.whenComplete { channelResult in
                        switch channelResult {
                        case .success(let childChannel):
                            let execRequest = SSHChannelRequestEvent.ExecRequest(
                                command: command,
                                wantReply: true
                            )
                            childChannel.triggerUserOutboundEvent(execRequest, promise: nil)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        log("Output: \(result.prefix(200))")
        return result
    }

    func disconnect() {
        log("Disconnecting")
        try? channel?.close().wait()
        try? group?.syncShutdownGracefully()
        channel = nil
        group = nil
        isConnected = false
    }

    deinit {
        try? group?.syncShutdownGracefully()
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[SlyAI SSH] \(timestamp) \(message)")
    }
}

// MARK: - Exec Data Handler

final class ExecDataHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData

    private let command: String
    private var output = ""
    private var continuation: CheckedContinuation<String, Error>?
    private var hasResumed = false

    init(command: String, continuation: CheckedContinuation<String, Error>) {
        self.command = command
        self.continuation = continuation
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)

        guard case .byteBuffer(let buffer) = channelData.data,
              let str = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) else {
            return
        }

        switch channelData.type {
        case .channel:
            output += str
        case .stdErr:
            output += "[stderr] \(str)"
        default:
            break
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        guard !hasResumed else { return }
        hasResumed = true
        continuation?.resume(returning: output.isEmpty ? "(no output)" : output)
        continuation = nil
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        guard !hasResumed else { return }
        hasResumed = true
        continuation?.resume(throwing: error)
        continuation = nil
        context.close(promise: nil)
    }
}

// MARK: - Errors

enum SSHError: LocalizedError {
    case notConnected
    case authenticationFailed
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to host"
        case .authenticationFailed: return "Authentication failed"
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        }
    }
}

// MARK: - Auth Delegates

final class PasswordAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    let username: String
    let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        if availableMethods.contains(.password) {
            nextChallengePromise.succeed(
                NIOSSHUserAuthenticationOffer(
                    username: username,
                    serviceName: "",
                    offer: .password(.init(password: password))
                )
            )
        } else {
            nextChallengePromise.succeed(nil)
        }
    }
}

final class PrivateKeyAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    let username: String
    let keyPath: String

    init(username: String, keyPath: String) {
        self.username = username
        self.keyPath = keyPath
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        nextChallengePromise.succeed(nil)
    }
}

final class AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        validationCompletePromise.succeed(())
    }
}
