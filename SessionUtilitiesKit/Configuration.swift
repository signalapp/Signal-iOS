
@objc(SNUtilitiesKitConfiguration)
public final class Configuration : NSObject {
    @objc public let owsPrimaryStorage: OWSPrimaryStorageProtocol
    public let maxFileSize: UInt

    @objc public static var shared: Configuration!

    fileprivate init(owsPrimaryStorage: OWSPrimaryStorageProtocol, maxFileSize: UInt) {
        self.owsPrimaryStorage = owsPrimaryStorage
        self.maxFileSize = maxFileSize
    }
}

public enum SessionUtilitiesKit { // Just to make the external API nice

    public static func configure(owsPrimaryStorage: OWSPrimaryStorageProtocol, maxFileSize: UInt) {
        Configuration.shared = Configuration(owsPrimaryStorage: owsPrimaryStorage, maxFileSize: maxFileSize)
    }
}
