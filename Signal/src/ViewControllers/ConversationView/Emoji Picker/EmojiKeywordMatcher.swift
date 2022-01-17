//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class EmojiKeywordMatcher {
    private var tree: Node
    private let availableEmojiByCategory: [Emoji.Category: [EmojiWithSkinTones]]
    private var searchKeywords = [String.SubSequence]()
    
    init(availableEmojiByCategory: [Emoji.Category: [EmojiWithSkinTones]]) {
        self.availableEmojiByCategory = availableEmojiByCategory
        tree = EmojiKeywordMatcher.buildEmojiSearchTree(fromEmoji: availableEmojiByCategory)
    }
    
    /// Searches the trie for matching emoji given the search string
    /// Runs in O(1) time with respect to the number of emoji being searched
    func getMatchingEmoji(searchString: String) -> [Emoji.Category: [EmojiWithSkinTones]] {
        searchKeywords = searchString
            .split(whereSeparator: { $0.isWhitespace })
            .sorted(by: { $0.count > $1.count })
        
        guard searchKeywords.count > 0 else {
            return availableEmojiByCategory
        }
        
        var result = [Emoji.Category: [EmojiWithSkinTones]]()
        
        for searchKeyword in searchKeywords {
            result = result.merging(searchTree(for: String(searchKeyword).lowercased(), currentNode: tree)) { (_, new) in new }
        }
        
        return result
    }
    
    private func searchTree(for partialKeyword: String, currentNode: Node) -> [Emoji.Category: [EmojiWithSkinTones]] {
        if partialKeyword.isEmpty {
            return currentNode.value
        }
        let nextNodeChar = partialKeyword.first!
        let nextPartialKeyword = String(partialKeyword.dropFirst())
        guard let nextNode = currentNode.children[nextNodeChar] else {
            return [:]
        }
        return searchTree(for: nextPartialKeyword, currentNode: nextNode)
    }
    
    /// A node in the trie lookup data structure
    /// It contains the emoji which match, up to the current character
    ///  and contains further character options in its children
    private class Node {
        var value: [Emoji.Category: [EmojiWithSkinTones]]
        var children: [Character: Node] = [:]
        
        init(value: [Emoji.Category: [EmojiWithSkinTones]]) {
            self.value = value
        }
    }
    
    /// Builds the trie data structure for matching emoji by keyword
    /// Runs in O(n+m) time where n is the number of emoji and m is the number of tags
    /// Only needs to be run once on initialization of this class
    private static func buildEmojiSearchTree(fromEmoji: [Emoji.Category: [EmojiWithSkinTones]]) -> Node {
        let rootNode = Node(value: [:])
        
        // We first build a lookup dictionary to prevent having to filter every emoji in the loop below
        // This allows us to reducce the complexity from O(nm) to O(n+m)
        let emojiToEmojiWithSkinTones = fromEmoji.reduce([Emoji: (Emoji.Category, EmojiWithSkinTones)]()) { (lookup, element) in
            let (category, emoji) = element
            var newLookup = lookup
            for emojiWithSkinTones in emoji {
                newLookup[emojiWithSkinTones.baseEmoji] = (category, emojiWithSkinTones)
            }
            return newLookup
        }
        
        // For each keyword, we build a subtree, appending all the matching emoji for each partial form of the keyword
        for keyword in emojiTags.keys {
            let matchingEmoji = emojiTags[keyword]!
            let filteredEmojisByCategory = matchingEmoji.reduce([Emoji.Category: [EmojiWithSkinTones]]()) { (filtered, emoji) in
                var newFiltered = filtered
                guard let (category, emojiWithSkinTones) = emojiToEmojiWithSkinTones[emoji] else {
                    return newFiltered
                }
                var emojiForCategory = newFiltered[category] ?? []
                emojiForCategory.append(emojiWithSkinTones)
                newFiltered[category] = emojiForCategory
                return newFiltered
            }
            buildSubTree(partialKeyword: keyword,
                         matchingEmoji: filteredEmojisByCategory,
                         currentNode: rootNode)
        }
        
        return rootNode
    }
    
    private static func buildSubTree(partialKeyword: String, matchingEmoji: [Emoji.Category: [EmojiWithSkinTones]], currentNode: Node) {
        if partialKeyword.isEmpty {
            return
        }
        let nextNodeChar = partialKeyword.first!
        let nextPartialKeyword = String(partialKeyword.dropFirst())
        let nextNode = currentNode.children[nextNodeChar] ?? Node(value: [:])
        nextNode.value = nextNode.value.merging(matchingEmoji) { (old, new) in Array(Set(old + new)) }
        currentNode.children[nextNodeChar] = nextNode
        buildSubTree(partialKeyword: nextPartialKeyword, matchingEmoji: matchingEmoji, currentNode: nextNode)
    }
}
