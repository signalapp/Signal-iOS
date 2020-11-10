
@objc public final class ClosedGroupParser : NSObject {
    private let data: Data
    
    @objc public init(data: Data) {
        self.data = data
    }
    
    @objc public func parseGroupModels() -> [TSGroupModel] {
        var index = 0
        var result: [TSGroupModel] = []
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
            guard let proto = try? SSKProtoGroupDetails.parseData(protoAsData) else { break }
            index += sizeAsInt
            var groupModel = TSGroupModel(title: proto.name, memberIds: proto.members, image: nil,
                groupId: proto.id, groupType: GroupType.closedGroup, adminIds: proto.admins)
            result.append(groupModel)
        }
        return result
    }
}
