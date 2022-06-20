extension Storage {
    
    private static let emojiPickerCollection = "EmojiPickerCollection"
    private static let recentEmojiKey = "recentEmoji"
    
    func getRecentEmoji(withDefaultEmoji: Bool, transaction: YapDatabaseReadTransaction) -> [EmojiWithSkinTones] {
        var rawRecentEmoji = transaction.object(forKey: Self.recentEmojiKey, inCollection: Self.emojiPickerCollection) as? [String] ?? []
        let defaultEmoji = ["🙈", "🙉", "🙊", "😈", "🥸", "🐀"].filter{ !rawRecentEmoji.contains($0) }
        
        if rawRecentEmoji.count < 6 && withDefaultEmoji {
            rawRecentEmoji.append(contentsOf: defaultEmoji[..<(defaultEmoji.count - rawRecentEmoji.count)])
        }
        
        return rawRecentEmoji.compactMap { EmojiWithSkinTones(rawValue: $0) }
    }
    
    func recordRecentEmoji(_ emoji: EmojiWithSkinTones, transaction: YapDatabaseReadWriteTransaction) {
        let recentEmoji = getRecentEmoji(withDefaultEmoji: false, transaction: transaction)
        guard recentEmoji.first != emoji else { return }
        guard emoji.isNormalized else {
            recordRecentEmoji(emoji.normalized, transaction: transaction)
            return
        }

        var newRecentEmoji = recentEmoji

        // Remove any existing entries for this emoji
        newRecentEmoji.removeAll { emoji == $0 }
        // Insert the selected emoji at the start of the list
        newRecentEmoji.insert(emoji, at: 0)
        // Truncate the recent emoji list to a maximum of 50 stored
        newRecentEmoji = Array(newRecentEmoji[0..<min(50, newRecentEmoji.count)])
        
        transaction.setObject(newRecentEmoji.map { $0.rawValue }, forKey: Self.recentEmojiKey, inCollection: Self.emojiPickerCollection)
    }
}
