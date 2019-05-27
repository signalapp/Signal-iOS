import PromiseKit

public extension LokiAPI {
    
    public struct Message {
        /// The hex encoded public key of the receiver.
        let destination: String
        /// The content of the message.
        let data: LosslessStringConvertible
        /// The time to live for the message in milliseconds.
        let ttl: UInt64
        /// Whether this message is a ping.
        ///
        /// - Note: The concept of pinging only applies to P2P messaging.
        let isPing: Bool
        /// When the proof of work was calculated, if applicable (P2P messages don't require proof of work).
        ///
        /// - Note: Expressed as milliseconds since 00:00:00 UTC on 1 January 1970.
        private(set) var timestamp: UInt64?
        /// The base 64 encoded proof of work, if applicable (P2P messages don't require proof of work).
        private(set) var nonce: String?
        
        private init(destination: String, data: LosslessStringConvertible, ttl: UInt64, isPing: Bool = false, timestamp: UInt64? = nil, nonce: String? = nil) {
            self.destination = destination
            self.data = data
            self.ttl = ttl
            self.isPing = isPing
            self.timestamp = timestamp
            self.nonce = nonce
        }
        
        /// Construct a `LokiMessage` from a `SignalMessage`.
        ///
        /// - Note: `timestamp` is the original message timestamp (i.e. `TSOutgoingMessage.timestamp`).
        public static func from(signalMessage: SignalMessage, timestamp: UInt64) -> Message? {
            // To match the desktop application, we have to wrap the data in an envelope and then wrap that in a websocket object
            do {
                let wrappedMessage = try LokiMessageWrapper.wrap(message: signalMessage, timestamp: timestamp)
                let data = wrappedMessage.base64EncodedString()
                let destination = signalMessage["destination"] as! String
                var ttl = LokiAPI.defaultMessageTTL
                if let messageTTL = signalMessage["ttl"] as! UInt?, messageTTL > 0 { ttl = UInt64(messageTTL) }
                let isPing = signalMessage["isPing"] as! Bool
                return Message(destination: destination, data: data, ttl: ttl, isPing: isPing)
            } catch let error {
                Logger.debug("[Loki] Failed to convert Signal message to Loki message: \(signalMessage).")
                return nil
            }
        }
        
        /// Calculate the proof of work for this message.
        ///
        /// - Returns: The promise of a new message with its `timestamp` and `nonce` set.
        public func calculatePoW() -> Promise<Message> {
            return Promise<Message> { seal in
                DispatchQueue.global(qos: .default).async {
                    let now = NSDate.ows_millisecondTimeStamp()
                    let dataAsString = self.data as! String // Safe because of the way from(signalMessage:timestamp:) is implemented
                    if let nonce = ProofOfWork.calculate(data: dataAsString, pubKey: self.destination, timestamp: now, ttl: self.ttl) {
                        var result = self
                        result.timestamp = now
                        result.nonce = nonce
                        seal.fulfill(result)
                    } else {
                        seal.reject(Error.proofOfWorkCalculationFailed)
                    }
                }
            }
        }

        public func toJSON() -> JSON {
            var result = [ "pubKey" : destination, "data" : data.description, "ttl" : String(ttl) ]
            if let timestamp = timestamp, let nonce = nonce {
                result["timestamp"] = String(timestamp)
                result["nonce"] = nonce
            }
            return result
        }
    }
}
