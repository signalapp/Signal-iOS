
@objc public final class ContactParser : NSObject {
    private let data: Data
    
    @objc public init(data: Data) {
        self.data = data
    }
    
    @objc public func parseHexEncodedPublicKeys() -> [String] {
        var index = 0
        var result: [String] = []
        while index < data.endIndex {
            let uncheckedSize: Int? = try? data[index..<(index+1)].withUnsafeBytes { $0.pointee }
            guard let size = uncheckedSize else { break }
            index += 1
            let protoAsData = data[index..<(index+size)]
            guard let proto = try? SSKProtoContactDetails.parseData(protoAsData) else { break }
            result.append(proto.number)
        }
        return result
    }
}
