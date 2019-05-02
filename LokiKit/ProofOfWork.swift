import CryptoSwift

private extension Int {
    init(_ decimal: Decimal) {
        let double = NSDecimalNumber(decimal: decimal).doubleValue
        self.init(double)
    }
}

private extension UInt8 {
    init(_ decimal: Decimal) {
        self.init(Int(decimal))
    }
}

private extension Decimal {
    /// Get the remainder of a Decimal
    static func %(lhs: Decimal, rhs: Int) -> Decimal {
        return Decimal(Int(lhs) % rhs)
    }
    
    /// Divide a Decimal by an Int
    static func /(lhs: Decimal, rhs: Int) -> Decimal {
        return lhs / Decimal(rhs)
    }

    /// Convert a Decimal to a UInt8 array of a given length
    func toArray(ofLength length: Int) -> [UInt8] {
        return (0..<length).map { i in
            let n = length - (i + 1)
            // 256 ** n is the value of one bit in arr[i], modulus to carry over
            // (self / 256**n) % 256;
            let denominator = pow(256, n)
            let fraction = self / denominator
            
            // fraction % 256
            let remainder = fraction % 256
            return UInt8(remainder)
        }
    }
}

// UInt8 Array specific stuff we need
private extension Array where Element == UInt8 {
    
    /// Compare if lhs array is greater than rhs array
    static func >(lhs: [UInt8], rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        
        // lhs is greater than rhs if any value in lhs is greater than the corresponding value in the rhs
        return zip(lhs, rhs).contains { $0 > $1 }
    }
    
    
    /// Increment the UInt8 array by a given amount
    ///
    /// - Parameter amount: The amount to increment by
    /// - Returns: The incrememnted array
    func increment(by amount: Int) -> [UInt8] {
        var newNonce = [UInt8](self)
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
    
    static let nonceLength = 8

    // Modify this value for difficulty scaling
    enum NonceTrials {
        static let development = 10
        static let production = 100
    }
    
    public struct Configuration {
        var pubKey: String
        var data: String
        var timestamp: Date
        var ttl: UInt
        var isDevelopment = false
        
        func getPayload() -> [UInt8] {
            let timestampString = String(timestamp.timeIntervalSince1970)
            let ttlString = String(ttl)
            let payloadString = timestampString + ttlString + pubKey + data
            return [UInt8](payloadString.utf8)
        }
    }
    
    
    /// Calculate a proof of work for the given configuration
    ///
    /// Ref: https://bitmessage.org/wiki/Proof_of_work
    ///
    /// - Parameter config: The configuration data
    /// - Returns: A nonce string or nil if it failed
    public static func calculate(with config: Configuration) -> String? {
        let payload = config.getPayload()
        let nonceTrials = config.isDevelopment ? NonceTrials.development : NonceTrials.production
        let target = calcTarget(ttl: config.ttl, payloadLength: payload.count, nonceTrials: nonceTrials)
        
        // Ref: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number/MAX_SAFE_INTEGER
        let maxSafeInteger = pow(2, 53) - 1
        var trialValue = maxSafeInteger.toArray(ofLength: nonceLength)
        
        let initialHash = [UInt8](config.data.sha512().utf8)
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
    private static func calcTarget(ttl: UInt, payloadLength: Int, nonceTrials: Int) -> [UInt8] {
        let decimalTTL = Decimal(ttl)
        let decimalPayloadLength = Decimal(payloadLength)
        let decimalNonceTrials = Decimal(nonceTrials)
        
        let decimalTwo16 = pow(2, 16) - 1
        let decimalTwo64 = pow(2, 64) - 1
        
        // ttl converted to seconds
        let ttlSeconds = decimalTTL / 1000
    
        // Do all the calculations
        let totalLength = decimalPayloadLength + Decimal(nonceLength)
        let ttlMult = ttlSeconds * totalLength
        let innerFrac = ttlMult / decimalTwo16
        let lenPlusInnerFrac = totalLength + innerFrac
        let denominator = decimalNonceTrials * lenPlusInnerFrac
        let targetNum = decimalTwo64 / Int(denominator)

        return targetNum.toArray(ofLength: nonceLength)
    }
}
