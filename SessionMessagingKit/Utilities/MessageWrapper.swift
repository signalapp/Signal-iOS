import SessionSnodeKit
import SessionUtilitiesKit

public enum MessageWrapper {

    public enum Error : LocalizedError {
        case failedToWrapData
        case failedToWrapMessageInEnvelope
        case failedToWrapEnvelopeInWebSocketMessage
        case failedToUnwrapData

        public var errorDescription: String? {
            switch self {
            case .failedToWrapData: return "Failed to wrap data."
            case .failedToWrapMessageInEnvelope: return "Failed to wrap message in envelope."
            case .failedToWrapEnvelopeInWebSocketMessage: return "Failed to wrap envelope in web socket message."
            case .failedToUnwrapData: return "Failed to unwrap data."
            }
        }
    }

    /// Wraps the given parameters in an `SNProtoEnvelope` and then a `WebSocketProtoWebSocketMessage` to match the desktop application.
    public static func wrap(type: SNProtoEnvelope.SNProtoEnvelopeType, timestamp: UInt64, senderPublicKey: String, base64EncodedContent: String) throws -> Data {
        do {
            let envelope = try createEnvelope(type: type, timestamp: timestamp, senderPublicKey: senderPublicKey, base64EncodedContent: base64EncodedContent)
            let webSocketMessage = try createWebSocketMessage(around: envelope)
            return try webSocketMessage.serializedData()
        } catch let error {
            throw error as? Error ?? Error.failedToWrapData
        }
    }

    private static func createEnvelope(type: SNProtoEnvelope.SNProtoEnvelopeType, timestamp: UInt64, senderPublicKey: String, base64EncodedContent: String) throws -> SNProtoEnvelope {
        do {
            let builder = SNProtoEnvelope.builder(type: type, timestamp: timestamp)
            builder.setSource(senderPublicKey)
            builder.setSourceDevice(1)
            if let content = Data(base64Encoded: base64EncodedContent, options: .ignoreUnknownCharacters) {
                builder.setContent(content)
            } else {
                throw Error.failedToWrapMessageInEnvelope
            }
            return try builder.build()
        } catch let error {
            SNLog("Failed to wrap message in envelope: \(error).")
            throw Error.failedToWrapMessageInEnvelope
        }
    }

    private static func createWebSocketMessage(around envelope: SNProtoEnvelope) throws -> WebSocketProtoWebSocketMessage {
        do {
            let requestBuilder = WebSocketProtoWebSocketRequestMessage.builder(verb: "PUT", path: "/api/v1/message", requestID: UInt64.random(in: 1..<UInt64.max))
            requestBuilder.setBody(try envelope.serializedData())
            let messageBuilder = WebSocketProtoWebSocketMessage.builder(type: .request)
            messageBuilder.setRequest(try requestBuilder.build())
            return try messageBuilder.build()
        } catch let error {
            SNLog("Failed to wrap envelope in web socket message: \(error).")
            throw Error.failedToWrapEnvelopeInWebSocketMessage
        }
    }

    /// - Note: `data` shouldn't be base 64 encoded.
    public static func unwrap(data: Data) throws -> SNProtoEnvelope {
        do {
            let webSocketMessage = try WebSocketProtoWebSocketMessage.parseData(data)
            let envelope = webSocketMessage.request!.body!
            return try SNProtoEnvelope.parseData(envelope)
        } catch let error {
            SNLog("Failed to unwrap data: \(error).")
            throw Error.failedToUnwrapData
        }
    }
}
