//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

protocol SelectionHapticFeedbackAdapter {
    func selectionChanged()
}

class SelectionHapticFeedback: SelectionHapticFeedbackAdapter {
    let adapter: SelectionHapticFeedbackAdapter

    init() {
        if #available(iOS 10, *) {
            adapter = ModernSelectionHapticFeedbackAdapter()
        } else {
            adapter = LegacySelectionHapticFeedbackAdapter()
        }
    }

    func selectionChanged() {
        adapter.selectionChanged()
    }
}

class LegacySelectionHapticFeedbackAdapter: NSObject, SelectionHapticFeedbackAdapter {
    func selectionChanged() {
        // do nothing
    }
}

@available(iOS 10, *)
class ModernSelectionHapticFeedbackAdapter: NSObject, SelectionHapticFeedbackAdapter {
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
