import CryptoSwift

/// Based on [mnemonic.js](https://github.com/loki-project/loki-messenger/blob/development/libloki/modules/mnemonic.js) .
enum Mnemonic {
    
    struct Language : Hashable {
        let filename: String
        let prefixLength: Int
        
        static let english = Language(filename: "english", prefixLength: 3)
        static let japanese = Language(filename: "japanese", prefixLength: 3)
        static let portuguese = Language(filename: "portuguese", prefixLength: 4)
        static let spanish = Language(filename: "spanish", prefixLength: 4)
        
        private static var wordSetCache: [Language:[String]] = [:]
        private static var truncatedWordSetCache: [Language:[String]] = [:]
        
        private init(filename: String, prefixLength: Int) {
            self.filename = filename
            self.prefixLength = prefixLength
        }
        
        func loadWordSet() -> [String] {
            if let cachedResult = Language.wordSetCache[self] {
                return cachedResult
            } else {
                let url = Bundle.main.url(forResource: filename, withExtension: "txt")!
                let contents = try! String(contentsOf: url)
                let result = contents.split(separator: ",").map { String($0) }
                Language.wordSetCache[self] = result
                return result
            }
        }
        
        func loadTruncatedWordSet() -> [String] {
            if let cachedResult = Language.truncatedWordSetCache[self] {
                return cachedResult
            } else {
                let result = loadWordSet().map { $0.prefix(length: prefixLength) }
                Language.truncatedWordSetCache[self] = result
                return result
            }
        }
    }
    
    enum DecodingError : Error {
        case generic, inputTooShort, missingLastWord, invalidWord, verificationFailed
    }
    
    static func encode(hexEncodedString string: String, language: Language = .english) -> String {
        var string = string
        let wordSet = language.loadWordSet()
        let prefixLength = language.prefixLength
        var result: [String] = []
        let n = wordSet.count
        let characterCount = string.indices.count
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
    
    static func decode(mnemonic: String, language: Language = .english) throws -> String {
        var words = mnemonic.split(separator: " ").map { String($0) }
        let truncatedWordSet = language.loadTruncatedWordSet()
        let prefixLength = language.prefixLength
        var result = ""
        let n = truncatedWordSet.count
        // Check preconditions
        guard words.count >= 12 else { throw DecodingError.inputTooShort }
        guard words.count % 3 != 0 else { throw DecodingError.missingLastWord }
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
    
    private static func determineChecksumIndex(for x: [String], prefixLength: Int) -> Int {
        let checksum = Array(x.map { $0.prefix(length: prefixLength) }.joined().utf8).crc32()
        return Int(checksum) % x.count
    }
}

private extension String {
    
    func prefix(length: Int) -> String {
        return String(self[startIndex..<index(startIndex, offsetBy: length)])
    }
}
