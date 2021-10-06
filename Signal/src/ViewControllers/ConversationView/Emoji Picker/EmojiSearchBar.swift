//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class EmojiSearchBar: UISearchBar {
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        placeholder = "Search emojis"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
