import SessionSnodeKit
import SessionUtilitiesKit

enum ProofOfWork {

    /// A modified version of [Bitmessage's Proof of Work Implementation](https://bitmessage.org/wiki/Proof_of_work).
    static func calculate(ttl: UInt64, publicKey: String, data: String) -> (timestamp: UInt64, base64EncodedNonce: String)? {
        let nonceSize = MemoryLayout<UInt64>.size
        // Get millisecond timestamp
        let timestamp = NSDate.millisecondTimestamp()
        // Construct payload
        let payloadAsString = String(timestamp) + String(ttl) + publicKey + data
        let payload = payloadAsString.bytes
        // Calculate target
        let numerator = UInt64.max
        let difficulty = UInt64(1)
        let totalSize = UInt64(payload.count + nonceSize)
        let ttlInSeconds = ttl / 1000
        let denominator = difficulty * (totalSize + (ttlInSeconds * totalSize) / UInt64(UInt16.max))
        let target = numerator / denominator
        // Calculate proof of work
        var value = UInt64.max
        let payloadHash = payload.sha512()
        var nonce = UInt64(0)
        while value > target {
            nonce = nonce &+ 1
            let hash = (nonce.bigEndianBytes + payloadHash).sha512()
            guard let newValue = UInt64(fromBigEndianBytes: [UInt8](hash[0..<nonceSize])) else { return nil }
            value = newValue
        }
        // Encode as base 64
        let base64EncodedNonce = nonce.bigEndianBytes.toBase64()
        // Return
        return (timestamp, base64EncodedNonce)
    }
}
