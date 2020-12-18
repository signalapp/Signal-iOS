
@objc
public final class SNUtilitiesKitConfiguration : NSObject {
    @objc public let owsPrimaryStorage: OWSPrimaryStorageProtocol
    public let maxFileSize: UInt

    @objc public static var shared: SNUtilitiesKitConfiguration!

    fileprivate init(owsPrimaryStorage: OWSPrimaryStorageProtocol, maxFileSize: UInt) {
        self.owsPrimaryStorage = owsPrimaryStorage
        self.maxFileSize = maxFileSize
    }
}

public enum SNUtilitiesKit { // Just to make the external API nice

    public static func configure(owsPrimaryStorage: OWSPrimaryStorageProtocol, maxFileSize: UInt) {
        SNUtilitiesKitConfiguration.shared = SNUtilitiesKitConfiguration(owsPrimaryStorage: owsPrimaryStorage, maxFileSize: maxFileSize)
    }
}
