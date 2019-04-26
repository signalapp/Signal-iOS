import CryptoSwift

enum Mnemonic {
    
    struct Language : Hashable {
        let filename: String
        let prefixLength: Int
        
        static let english = Language(filename: "english", prefixLength: 3)
        static let japanese = Language(filename: "japanese", prefixLength: 3)
        static let portuguese = Language(filename: "portuguese", prefixLength: 4)
        static let spanish = Language(filename: "spanish", prefixLength: 4)
        
        private static var wordSetCache: [Language:[String]] = [:]
        
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
    }
    
    /// Based on [mnemonic.js](https://github.com/loki-project/loki-messenger/blob/development/libloki/modules/mnemonic.js) .
    static func encode(hexEncodedString string: String, language: Language = .english) -> String {
        var string = string
        let wordSet = language.loadWordSet()
        let prefixLength = language.prefixLength
        var result: [String] = []
        let wordCount = wordSet.count
        let characterCount = string.indices.count // Safe for this particular case
        for chunkStartIndexAsInt in stride(from: 0, to: characterCount, by: 8) {
            let chunkStartIndex = string.index(string.startIndex, offsetBy: chunkStartIndexAsInt)
            let chunkEndIndex = string.index(chunkStartIndex, offsetBy: 8)
            func swap(_ chunk: String) -> String {
                func toStringIndex(_ indexAsInt: Int) -> String.Index {
                    return chunk.index(chunk.startIndex, offsetBy: indexAsInt)
                }
                let p1 = chunk[toStringIndex(6)..<toStringIndex(8)]
                let p2 = chunk[toStringIndex(4)..<toStringIndex(6)]
                let p3 = chunk[toStringIndex(2)..<toStringIndex(4)]
                let p4 = chunk[toStringIndex(0)..<toStringIndex(2)]
                return String(p1 + p2 + p3 + p4)
            }
            let p1 = string[string.startIndex..<chunkStartIndex]
            let p2 = swap(String(string[chunkStartIndex..<chunkEndIndex]))
            let p3 = string[chunkEndIndex..<string.endIndex]
            string = String(p1 + p2 + p3)
        }
        for chunkStartIndexAsInt in stride(from: 0, to: characterCount, by: 8) {
            let chunkStartIndex = string.index(string.startIndex, offsetBy: chunkStartIndexAsInt)
            let chunkEndIndex = string.index(chunkStartIndex, offsetBy: 8)
            let x = Int(string[chunkStartIndex..<chunkEndIndex], radix: 16)!
            let w1 = x % wordCount
            let w2 = ((x / wordCount) + w1) % wordCount
            let w3 = (((x / wordCount) / wordCount) + w2) % wordCount
            result += [ wordSet[w1], wordSet[w2], wordSet[w3] ]
        }
        let checksum = Array(result.map { String($0[$0.startIndex..<$0.index($0.startIndex, offsetBy: prefixLength)]) }.joined().utf8).crc32()
        let checksumIndex = Int(checksum) % result.count
        result.append(result[checksumIndex])
        return result.joined(separator: " ")
    }
}
