import PromiseKit

public final class OpenGroupManager : OpenGroupManagerProtocol {

    public enum Error : LocalizedError {
        case invalidURL

        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL."
            }
        }
    }

    public static let shared = OpenGroupManager()

    private init() { }

    public func addOpenGroup(with url: String) -> Promise<Void> {
        guard let url = URL(string: url), let scheme = url.scheme, scheme == "https", url.host != nil else {
            return Promise(error: Error.invalidURL)
        }
        let channelID: UInt64 = 1
        let urlAsString = url.absoluteString
        let userPublicKey = getUserHexEncodedPublicKey()
        let profileManager = OWSProfileManager.shared()
        let displayName = profileManager.profileNameForRecipient(withID: userPublicKey)
        let profilePictureURL = profileManager.profilePictureURL()
        let profileKey = profileManager.localProfileKey().keyData
        Storage.writeSync { transaction in
            transaction.removeObject(forKey: "\(urlAsString).\(channelID)", inCollection: Storage.lastMessageServerIDCollection)
            transaction.removeObject(forKey: "\(urlAsString).\(channelID)", inCollection: Storage.lastDeletionServerIDCollection)
        }
        return PublicChatManager.shared.addChat(server: urlAsString, channel: channelID).done(on: DispatchQueue.main) { _ in
            let _ = OpenGroupAPI.setDisplayName(to: displayName, on: urlAsString)
            let _ = OpenGroupAPI.setProfilePictureURL(to: profilePictureURL, using: profileKey, on: urlAsString)
            let _ = OpenGroupAPI.join(channelID, on: urlAsString)
        }
    }
}
