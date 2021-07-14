//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class HVViewState: NSObject {
    public let threadMapping = ThreadMapping()
}

// MARK: -

@objc
public extension ConversationListViewController {
    var threadMapping: ThreadMapping { viewState.threadMapping }
}
