
@objc(SNAttachmentStream)
public protocol AttachmentStream {
    @objc var encryptionKey: Data { get set }
    @objc var digest: Data { get set }
    @objc var serverId: UInt64 { get set }
    @objc var isUploaded: Bool { get set }
    @objc var downloadURL: String { get set }

    @objc func readDataFromFile() throws -> Data
    @objc func save()
}
