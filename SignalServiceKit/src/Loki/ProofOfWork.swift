import CryptoSwift

private extension UInt64 {
    
    init(_ decimal: Decimal) {
        self.init(truncating: decimal as NSDecimalNumber)
    }
    
    // Convert a UInt8 array to a UInt64
    init(_ bytes: [UInt8]) {
        precondition(bytes.count <= MemoryLayout<UInt64>.size)
        var value: UInt64 = 0
        for byte in bytes {
            value <<= 8
            value |= UInt64(byte)
        }
        self.init(value)
    }
}

private extension MutableCollection where Element == UInt8, Index == Int {

    /// Increment every element by the given amount
    ///
    /// - Parameter amount: The amount to increment by
    /// - Returns: The incremented collection
    func increment(by amount: Int) -> Self {
        var result = self
        var increment = amount
        for i in (0..<result.count).reversed() {
            guard increment > 0 else { break }
            let sum = Int(result[i]) + increment
            result[i] = UInt8(sum % 256)
            increment = sum / 256
        }
        return result
    }
}

/**
 * The main proof of work logic.
 *
 * This was copied from the desktop messenger.
 * Ref: libloki/proof-of-work.js
 */
@objc public final class ProofOfWork : NSObject {
    
    // If this changes then we also have to use something other than UInt64 to support the new length
    private static let nonceLength = 8

    private static let nonceTrialCount: Int = {
        switch BuildConfiguration.current {
        case .debug: return 10
        case .production: return 100
        }
    }()

    private override init() { }
    
    /// Calculate a proof of work with the given configuration
    ///
    /// Ref: https://bitmessage.org/wiki/Proof_of_work
    ///
    /// - Parameters:
    ///   - data: The message data
    ///   - pubKey: The message recipient
    ///   - timestamp: The timestamp
    ///   - ttl: The message time to live
    /// - Returns: A nonce string or nil if it failed
    @objc public static func calculate(data: String, pubKey: String, timestamp: UInt64, ttl: Int) -> String? {
        let payload = getPayload(pubKey: pubKey, data: data, timestamp: timestamp, ttl: ttl)
        let target = calcTarget(ttl: ttl, payloadLength: payload.count, nonceTrials: nonceTrialCount)
        
        // Start with the max value
        var trialValue = UInt64.max
        
        let initialHash = payload.sha512()
        var nonce = [UInt8](repeating: 0, count: nonceLength)
    
        while trialValue > target {
            nonce = nonce.increment(by: 1)
            
            // This is different to the bitmessage POW
            // resultHash = hash(nonce + hash(data)) ==> hash(nonce + initialHash)
            let resultHash = (nonce + initialHash).sha512()
            let trialValueArray = Array(resultHash[0..<8])
            trialValue = UInt64(trialValueArray)
        }
        
        return nonce.toBase64()
    }
    
    /// Get the proof of work payload
    private static func getPayload(pubKey: String, data: String, timestamp: UInt64, ttl: Int) -> [UInt8] {
        let timestampString = String(timestamp)
        let ttlString = String(ttl)
        let payloadString = timestampString + ttlString + pubKey + data
        return payloadString.bytes
    }
    
    /// Calculate the target we need to reach
    private static func calcTarget(ttl: Int, payloadLength: Int, nonceTrials: Int) -> UInt64 {
        let two16 = UInt64(pow(2, 16) - 1)
        let two64 = UInt64(pow(2, 64) - 1)
  
        // ttl converted to seconds
        let ttlSeconds = ttl / 1000

        // Do all the calculations
        let totalLength = UInt64(payloadLength + nonceLength)
        let ttlMult = UInt64(ttlSeconds) * totalLength
        
        // UInt64 values
        let innerFrac = ttlMult / two16
        let lenPlusInnerFrac = totalLength + innerFrac
        let denominator = UInt64(nonceTrials) * lenPlusInnerFrac

        return two64 / denominator
    }
}
