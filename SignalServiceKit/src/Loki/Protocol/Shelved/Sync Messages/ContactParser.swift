
public final class ContactParser {
    private let data: Data
    
    public init(data: Data) {
        self.data = data
    }
    
    public func parse() -> [(publicKey: String, isBlocked: Bool)] {
        var index = 0
        var result: [(String, Bool)] = []
        while index < data.endIndex {
            var uncheckedSize: UInt32? = try? data[index..<(index+4)].withUnsafeBytes { $0.pointee }
            if let size = uncheckedSize, size >= data.count, let intermediate = try? data[index..<(index+4)].reversed() {
                uncheckedSize = Data(intermediate).withUnsafeBytes { $0.pointee }
            }
            guard let size = uncheckedSize, size < data.count else { break }
            let sizeAsInt = Int(size)
            index += 4
            guard index + sizeAsInt <= data.count else { break }
            let protoAsData = data[index..<(index+sizeAsInt)]
            guard let proto = try? SSKProtoContactDetails.parseData(protoAsData) else { break }
            index += sizeAsInt
            result.append((publicKey: proto.number, isBlocked: proto.blocked))
        }
        return result
    }
}
