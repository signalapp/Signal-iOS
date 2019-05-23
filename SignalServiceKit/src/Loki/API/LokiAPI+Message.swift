import PromiseKit

public extension LokiAPI {
    
    public struct Message {
        /// The hex encoded public key of the receiver.
        let destination: String
        /// The content of the message.
        let data: LosslessStringConvertible
        /// The time to live for the message in milliseconds.
        let ttl: UInt64
        /// When the proof of work was calculated, if applicable.
        ///
        /// - Note: Expressed as milliseconds since 00:00:00 UTC on 1 January 1970.
        var timestamp: UInt64? = nil
        /// The base 64 encoded proof of work, if applicable.
        var nonce: String? = nil
        
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
                if let messageTTL = signalMessage["ttl"] as? UInt, messageTTL > 0 { ttl = UInt64(messageTTL) }
                return Message(destination: destination, data: data, ttl: ttl, timestamp: nil, nonce: nil)
            } catch let error {
                Logger.debug("[Loki] Failed to convert Signal message to Loki message: \(signalMessage)")
                return nil
            }
        }
        
        /// Create a basic loki message.
        ///
        /// - Parameters:
        ///   - destination: The destination
        ///   - data: The data
        ///   - ttl: The time to live
        public init(destination: String, data: LosslessStringConvertible, ttl: UInt64) {
            self.destination = destination
            self.data = data
            self.ttl = ttl
        }
        
        /// Private init for setting proof of work. Use `calculatePoW` to get a message with these fields
        private init(destination: String, data: LosslessStringConvertible, ttl: UInt64, timestamp: UInt64?, nonce: String?) {
            self.destination = destination
            self.data = data
            self.ttl = ttl
            self.timestamp = timestamp
            self.nonce = nonce
        }
        
        /// Calculate the proof of work for this message
        ///
        /// - Returns: This will return a promise with a new message which contains the proof of work
        public func calculatePoW() -> Promise<Message> {
            // To match the desktop application, we have to wrap the data in an envelope and then wrap that in a websocket object
            return Promise<Message> { seal in
                DispatchQueue.global(qos: .default).async {
                    let now = NSDate.ows_millisecondTimeStamp()
                    let ttlInSeconds = ttl / 1000
                    if let nonce = ProofOfWork.calculate(data: self.data as! String, pubKey: self.destination, timestamp: now, ttl: ttlInSeconds) {
                        let result = Message(destination: self.destination, data: self.data, ttl: self.ttl, timestamp: now, nonce: nonce)
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
