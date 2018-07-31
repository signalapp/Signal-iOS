//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol HapticAdapter {
    func selectionChanged()
}

class LegacyHapticAdapter: NSObject, HapticAdapter {

    // MARK: HapticAdapter

    func selectionChanged() {
        // do nothing
    }
}

@available(iOS 10, *)
class FeedbackGeneratorHapticAdapter: NSObject, HapticAdapter {
    let selectionFeedbackGenerator: UISelectionFeedbackGenerator

    override init() {
        selectionFeedbackGenerator = UISelectionFeedbackGenerator()
        selectionFeedbackGenerator.prepare()
    }

    // MARK: HapticAdapter

    func selectionChanged() {
        selectionFeedbackGenerator.selectionChanged()
        selectionFeedbackGenerator.prepare()
    }
}

class HapticFeedback: HapticAdapter {
    let adapter: HapticAdapter

    init() {
        if #available(iOS 10, *) {
            adapter = FeedbackGeneratorHapticAdapter()
        } else {
            adapter = LegacyHapticAdapter()
        }
    }

    func selectionChanged() {
        adapter.selectionChanged()
    }
}
