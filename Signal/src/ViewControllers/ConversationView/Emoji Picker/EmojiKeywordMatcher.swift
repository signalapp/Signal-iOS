//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

struct EmojiKeywordMatcher {
    static let tree = buildEmojiSearchTree()
    private var searchKeywords: [String.SubSequence]
    
    public init(searchString: String) {
        searchKeywords = searchString
            .split(whereSeparator: { $0.isWhitespace })
            .sorted(by: { $0.count > $1.count })
    }
    
    func getMatchingEmoji() -> [Emoji] {
        guard searchKeywords.count > 0 else {
            return Emoji.allCases
        }
        
        var emoji = Set<Emoji>()
        
        for searchKeyword in searchKeywords {
            emoji.formUnion(searchTree(for: String(searchKeyword).lowercased()))
        }
        
        return Array(emoji)
    }
    
    func searchTree(for partialKeyword: String, currentNode: Node = tree) -> [Emoji] {
        if partialKeyword.isEmpty {
            return currentNode.value
        }
        let nextNodeChar = partialKeyword.first!
        let nextPartialKeyword = String(partialKeyword.dropFirst())
        guard let nextNode = currentNode.children[nextNodeChar] else {
            return []
        }
        return searchTree(for: nextPartialKeyword, currentNode: nextNode)
    }
    
    class Node {
        var value: [Emoji]
        var children: [Character: Node] = [:]
        
        init(value: [Emoji]) {
            self.value = value
        }
    }
    
    static func buildEmojiSearchTree() -> Node {
        let rootNode = Node(value: [])
        
        for keyword in emojiTags.keys {
            buildSubTree(partialKeyword: keyword, matchingEmoji: emojiTags[keyword]!
                         , currentNode: rootNode)
        }
        
        return rootNode
    }


    static func buildSubTree(partialKeyword: String, matchingEmoji: [Emoji], currentNode: Node) {
        if partialKeyword.isEmpty {
            return
        }
        let nextNodeChar = partialKeyword.first!
        let nextPartialKeyword = String(partialKeyword.dropFirst())
        let nextNode = currentNode.children[nextNodeChar] ?? Node(value: [])
        nextNode.value += matchingEmoji
        currentNode.children[nextNodeChar] = nextNode
        buildSubTree(partialKeyword: nextPartialKeyword, matchingEmoji: matchingEmoji, currentNode: nextNode)
    }
}
