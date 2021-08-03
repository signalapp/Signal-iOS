
@objc(LKMentionUtilities)
public final class MentionUtilities : NSObject {

    override private init() { }

    @objc public static func highlightMentions(in string: String, threadID: String) -> String {
        return highlightMentions(in: string, isOutgoingMessage: false, threadID: threadID, attributes: [:]).string // isOutgoingMessage and attributes are irrelevant
    }

    @objc public static func highlightMentions(in string: String, isOutgoingMessage: Bool, threadID: String, attributes: [NSAttributedString.Key:Any]) -> NSAttributedString {
        let openGroupV2 = Storage.shared.getV2OpenGroup(for: threadID)
        OWSPrimaryStorage.shared().dbReadConnection.read { transaction in
            MentionsManager.populateUserPublicKeyCacheIfNeeded(for: threadID, in: transaction)
        }
        var string = string
        let regex = try! NSRegularExpression(pattern: "@[0-9a-fA-F]{66}", options: [])
        let knownPublicKeys = MentionsManager.userPublicKeyCache[threadID] ?? [] // Should always be populated at this point
        var mentions: [(range: NSRange, publicKey: String)] = []
        var outerMatch = regex.firstMatch(in: string, options: .withoutAnchoringBounds, range: NSRange(location: 0, length: string.utf16.count))
        while let match = outerMatch {
            let publicKey = String((string as NSString).substring(with: match.range).dropFirst()) // Drop the @
            let matchEnd: Int
            if knownPublicKeys.contains(publicKey) {
                let context: Contact.Context = (openGroupV2 != nil) ? .openGroup : .regular
                let displayName = Storage.shared.getContact(with: publicKey)?.displayName(for: context)
                if let displayName = displayName {
                    string = (string as NSString).replacingCharacters(in: match.range, with: "@\(displayName)")
                    mentions.append((range: NSRange(location: match.range.location, length: displayName.utf16.count + 1), publicKey: publicKey)) // + 1 to include the @
                    matchEnd = match.range.location + displayName.utf16.count
                } else {
                    matchEnd = match.range.location + match.range.length
                }
            } else {
                matchEnd = match.range.location + match.range.length
            }
            outerMatch = regex.firstMatch(in: string, options: .withoutAnchoringBounds, range: NSRange(location: matchEnd, length: string.utf16.count - matchEnd))
        }
        let result = NSMutableAttributedString(string: string, attributes: attributes)
        mentions.forEach { mention in
            let color = isOutgoingMessage ? (isLightMode ? .white : .black) : Colors.accent
            result.addAttribute(.foregroundColor, value: color, range: mention.range)
            result.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: Values.smallFontSize), range: mention.range)
        }
        return result
    }
}
