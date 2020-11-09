
@objc public protocol AttachmentStream {
    var encryptionKey: Data { get set }
    var digest: Data { get set }
    var serverId: UInt64 { get set }
    var isUploaded: Bool { get set }
    var downloadURL: String { get set }

    func readDataFromFile() throws -> Data
    func save()
}
