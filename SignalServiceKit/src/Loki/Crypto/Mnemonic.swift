import CryptoSwift

/// Based on [mnemonic.js](https://github.com/loki-project/loki-messenger/blob/development/libloki/modules/mnemonic.js) .
public enum Mnemonic {
    
    public struct Language : Hashable {
        fileprivate let filename: String
        fileprivate let prefixLength: UInt
        
        public static let english = Language(filename: "english", prefixLength: 3)
        public static let japanese = Language(filename: "japanese", prefixLength: 3)
        public static let portuguese = Language(filename: "portuguese", prefixLength: 4)
        public static let spanish = Language(filename: "spanish", prefixLength: 4)
        
        private static var wordSetCache: [Language:[String]] = [:]
        private static var truncatedWordSetCache: [Language:[String]] = [:]
        
        private init(filename: String, prefixLength: UInt) {
            self.filename = filename
            self.prefixLength = prefixLength
        }
        
        fileprivate func loadWordSet() -> [String] {
            if let cachedResult = Language.wordSetCache[self] {
                return cachedResult
            } else {
                let bundleID = "org.cocoapods.SignalServiceKit"
                let url = Bundle(identifier: bundleID)!.url(forResource: filename, withExtension: "txt")!
                let contents = try! String(contentsOf: url)
                let result = contents.split(separator: ",").map { String($0) }
                Language.wordSetCache[self] = result
                return result
            }
        }
        
        fileprivate func loadTruncatedWordSet() -> [String] {
            if let cachedResult = Language.truncatedWordSetCache[self] {
                return cachedResult
            } else {
                let result = loadWordSet().map { $0.prefix(length: prefixLength) }
                Language.truncatedWordSetCache[self] = result
                return result
            }
        }
    }
    
    public enum DecodingError : LocalizedError {
        case generic, inputTooShort, missingLastWord, invalidWord, verificationFailed
        
        public var errorDescription: String? {
            switch self {
            case .generic: return NSLocalizedString("Something went wrong. Please check your mnemonic and try again.", comment: "")
            case .inputTooShort: return NSLocalizedString("Looks like you didn't enter enough words. Please check your mnemonic and try again.", comment: "")
            case .missingLastWord: return NSLocalizedString("You seem to be missing the last word of your mnemonic. Please check what you entered and try again.", comment: "")
            case .invalidWord: return NSLocalizedString("There appears to be an invalid word in your mnemonic. Please check what you entered and try again.", comment: "")
            case .verificationFailed: return NSLocalizedString("Your mnemonic couldn't be verified. Please check what you entered and try again.", comment: "")
            }
        }
    }
    
    public static func encode(hexEncodedString string: String, language: Language = .english) -> String {
        var string = string
        let wordSet = language.loadWordSet()
        let prefixLength = language.prefixLength
        var result: [String] = []
        let n = wordSet.count
        let characterCount = string.indices.count // Safe for this particular case
        for chunkStartIndexAsInt in stride(from: 0, to: characterCount, by: 8) {
            let chunkStartIndex = string.index(string.startIndex, offsetBy: chunkStartIndexAsInt)
            let chunkEndIndex = string.index(chunkStartIndex, offsetBy: 8)
            let p1 = string[string.startIndex..<chunkStartIndex]
            let p2 = swap(String(string[chunkStartIndex..<chunkEndIndex]))
            let p3 = string[chunkEndIndex..<string.endIndex]
            string = String(p1 + p2 + p3)
        }
        for chunkStartIndexAsInt in stride(from: 0, to: characterCount, by: 8) {
            let chunkStartIndex = string.index(string.startIndex, offsetBy: chunkStartIndexAsInt)
            let chunkEndIndex = string.index(chunkStartIndex, offsetBy: 8)
            let x = Int(string[chunkStartIndex..<chunkEndIndex], radix: 16)!
            let w1 = x % n
            let w2 = ((x / n) + w1) % n
            let w3 = (((x / n) / n) + w2) % n
            result += [ wordSet[w1], wordSet[w2], wordSet[w3] ]
        }
        let checksumIndex = determineChecksumIndex(for: result, prefixLength: prefixLength)
        let checksumWord = result[checksumIndex]
        result.append(checksumWord)
        return result.joined(separator: " ")
    }
    
    public static func decode(mnemonic: String, language: Language = .english) throws -> String {
        var words = mnemonic.split(separator: " ").map { String($0) }
        let truncatedWordSet = language.loadTruncatedWordSet()
        let prefixLength = language.prefixLength
        var result = ""
        let n = truncatedWordSet.count
        // Check preconditions
        guard words.count >= 12 else { throw DecodingError.inputTooShort }
        guard !words.count.isMultiple(of: 3) else { throw DecodingError.missingLastWord }
        // Get checksum word
        let checksumWord = words.popLast()!
        // Decode
        for chunkStartIndex in stride(from: 0, to: words.count, by: 3) {
            guard let w1 = truncatedWordSet.firstIndex(of: words[chunkStartIndex].prefix(length: prefixLength)),
                let w2 = truncatedWordSet.firstIndex(of: words[chunkStartIndex + 1].prefix(length: prefixLength)),
                let w3 = truncatedWordSet.firstIndex(of: words[chunkStartIndex + 2].prefix(length: prefixLength)) else { throw DecodingError.invalidWord }
            let x = w1 + n * ((n - w1 + w2) % n) + n * n * ((n - w2 + w3) % n)
            guard x % n == w1 else { throw DecodingError.generic }
            let string = "0000000" + String(x, radix: 16)
            result += swap(String(string[string.index(string.endIndex, offsetBy: -8)..<string.endIndex]))
        }
        // Verify checksum
        let checksumIndex = determineChecksumIndex(for: words, prefixLength: prefixLength)
        let expectedChecksumWord = words[checksumIndex]
        guard expectedChecksumWord.prefix(length: prefixLength) == checksumWord.prefix(length: prefixLength) else { throw DecodingError.verificationFailed }
        // Return
        return result
    }
    
    private static func swap(_ x: String) -> String {
        func toStringIndex(_ indexAsInt: Int) -> String.Index {
            return x.index(x.startIndex, offsetBy: indexAsInt)
        }
        let p1 = x[toStringIndex(6)..<toStringIndex(8)]
        let p2 = x[toStringIndex(4)..<toStringIndex(6)]
        let p3 = x[toStringIndex(2)..<toStringIndex(4)]
        let p4 = x[toStringIndex(0)..<toStringIndex(2)]
        return String(p1 + p2 + p3 + p4)
    }
    
    private static func determineChecksumIndex(for x: [String], prefixLength: UInt) -> Int {
        let checksum = Array(x.map { $0.prefix(length: prefixLength) }.joined().utf8).crc32()
        return Int(checksum) % x.count
    }
}

private extension String {
    
    func prefix(length: UInt) -> String {
        return String(self[startIndex..<index(startIndex, offsetBy: Int(length))])
    }
}

@objc(LKMnemonic)
public final class ObjCMnemonic : NSObject {
    
    override private init() { }
    
    @objc(encodeHexEncodedString:)
    public static func encode(hexEncodedString string: String) -> String {
        return Mnemonic.encode(hexEncodedString: string)
    }
}
