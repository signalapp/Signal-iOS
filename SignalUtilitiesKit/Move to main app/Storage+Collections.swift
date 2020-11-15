
// TODO: Create an extension for each category, e.g. Storage+OpenGroups, Storage+SnodePool, etc.

@objc public extension Storage {

    // TODO: Add remaining collections

    @objc func getDeviceLinkCollection(for masterPublicKey: String) -> String {
        return "LokiDeviceLinkCollection-\(masterPublicKey)"
    }

    @objc public static func getSwarmCollection(for publicKey: String) -> String {
        return "LokiSwarmCollection-\(publicKey)"
    }

    @objc public static let openGroupCollection = "LokiPublicChatCollection"
    @objc public static let openGroupProfilePictureURLCollection = "LokiPublicChatAvatarURLCollection"
    @objc public static let openGroupUserCountCollection = "LokiPublicChatUserCountCollection"
    @objc public static let sessionRequestTimestampCollection = "LokiSessionRequestTimestampCollection"
    @objc public static let snodePoolCollection = "LokiSnodePoolCollection"
}
