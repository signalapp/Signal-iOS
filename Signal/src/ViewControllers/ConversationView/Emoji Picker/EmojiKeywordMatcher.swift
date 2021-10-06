//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

struct EmojiKeywordMatcher {
    private var searchKeywords: [String.SubSequence]
    
    public init(searchString: String) {
        searchKeywords = searchString
            .split(whereSeparator: { $0.isWhitespace })
            .sorted(by: { $0.count > $1.count })
    }
    
    func matches(_ candidate: Emoji) -> Bool {
        guard searchKeywords.count > 0 else {
            return true
        }
        
        for searchKeyword in searchKeywords {
            if candidate.name?.lowercased().contains(searchKeyword.lowercased()) ?? false {
                return true
            }
        }
        
        return false
    }
}
