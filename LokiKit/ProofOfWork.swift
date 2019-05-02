import CryptoSwift

private extension UInt64 {
    init(_ decimal: Decimal) {
        self.init(truncating: decimal as NSDecimalNumber)
    }
}

// UInt8 Array specific stuff we need
private extension Array where Element == UInt8 {
    
    // Convert a UInt64 into an array
    init(_ uint64: UInt64) {
        let array = stride(from: 0, to: 64, by: 8).reversed().map {
            UInt8(uint64 >> $0 & 0x000000FF)
        }
        self.init(array)
    }
    
    /// Compare if lhs array is greater than rhs array
    static func >(lhs: [UInt8], rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        
        for i in (0..<lhs.count) {
            // If the values are the same then move onto the next pair
            if (lhs[i] == rhs[i]) { continue }
            return lhs[i] > rhs[i]
        }
        return false
    }
    
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

    // Modify this value for difficulty scaling
    private enum NonceTrials {
        static let development = 10
        static let production = 100
    }
    
    struct Configuration {
        var pubKey: String
        var data: String
        var timestamp: Date
        var ttl: Int
        var isDevelopment = false
        
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
    static func calculate(with config: Configuration) -> String? {
        let payload = config.payload
        let nonceTrials = config.isDevelopment ? NonceTrials.development : NonceTrials.production
        let target = calcTarget(ttl: config.ttl, payloadLength: payload.count, nonceTrials: nonceTrials)
        
        // Ref: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number/MAX_SAFE_INTEGER
        let maxSafeInteger = UInt64(pow(2, 53) - 1)
        var trialValue = [UInt8](maxSafeInteger)
        
        let initialHash = payload.sha512()
        var nonce = [UInt8](repeating: 0, count: nonceLength)
    
        while trialValue > target {
            nonce = nonce.increment(by: 1)
            
            // This is different to the bitmessage pow
            // resultHash = hash(nonce + hash(data)) ==> hash(nonce + initialHash)
            let resultHash = (nonce + initialHash).sha512()
            trialValue = Array(resultHash[0..<8])
        }
        
        return nonce.toBase64()
    }
    
    /// Calculate the UInt8 target we need to reach
    private static func calcTarget(ttl: Int, payloadLength: Int, nonceTrials: Int) -> [UInt8] {
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
        let targetNum = two64 / denominator

        return [UInt8](targetNum)
    }
}
