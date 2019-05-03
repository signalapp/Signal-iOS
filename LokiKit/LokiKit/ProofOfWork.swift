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

// UInt8 Array specific stuff we need
private extension Array where Element == UInt8 {
    /// Increment the UInt8 array by a given amount
    ///
    /// - Parameter amount: The amount to increment by
    /// - Returns: The incrememnted array
    func increment(by amount: Int) -> [UInt8] {
        var newNonce = self
        var increment = amount
        for i in (0..<newNonce.count).reversed() {
            guard increment > 0 else { break }
            let sum = Int(newNonce[i]) + increment
            newNonce[i] = UInt8(sum % 256)
            increment = sum / 256
        }
        return newNonce
    }
}

/**
 * The main logic which handles proof of work.
 *
 * This was copied from the messenger desktop.
 *  Ref: libloki/proof-of-work.js
 */
public enum ProofOfWork {
    
    // If this changes then we also have to use something other than UInt64 to support the new length
    private static let nonceLength = 8

    private static let nonceTrialCount: Int = {
        switch BuildConfiguration.current {
        case .debug: return 10
        case .production: return 100
        }
    }()
    
    public struct Configuration {
        var pubKey: String
        var data: String
        var timestamp: Date
        var ttl: Int
        
        public init(pubKey: String, data: String, timestamp: Date, ttl: Int) {
            self.pubKey = pubKey
            self.data = data
            self.timestamp = timestamp
            self.ttl = ttl
        }
        
        var payload: [UInt8] {
            let timestampString = String(Int(timestamp.timeIntervalSince1970))
            let ttlString = String(ttl)
            let payloadString = timestampString + ttlString + pubKey + data
            return payloadString.bytes
        }
    }
    
    
    /// Calculate a proof of work for the given configuration
    ///
    /// Ref: https://bitmessage.org/wiki/Proof_of_work
    ///
    /// - Parameter config: The configuration data
    /// - Returns: A nonce string or nil if it failed
    public static func calculate(with config: Configuration) -> String? {
        let payload = config.payload
        let target = calcTarget(ttl: config.ttl, payloadLength: payload.count, nonceTrials: nonceTrialCount)
        
        // Start with the max value
        var trialValue = UInt64.max
        
        let initialHash = payload.sha512()
        var nonce = [UInt8](repeating: 0, count: nonceLength)
    
        while trialValue > target {
            nonce = nonce.increment(by: 1)
            
            // This is different to the bitmessage pow
            // resultHash = hash(nonce + hash(data)) ==> hash(nonce + initialHash)
            let resultHash = (nonce + initialHash).sha512()
            let trialValueArray = Array(resultHash[0..<8])
            trialValue = UInt64(trialValueArray)
        }
        
        return nonce.toBase64()
    }
    
    /// Calculate the UInt8 target we need to reach
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
