//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class SelectionHapticFeedback {
    let selectionFeedbackGenerator: UISelectionFeedbackGenerator

    init() {
        selectionFeedbackGenerator = UISelectionFeedbackGenerator()
        selectionFeedbackGenerator.prepare()
    }

    func selectionChanged() {
        selectionFeedbackGenerator.selectionChanged()
        selectionFeedbackGenerator.prepare()
    }
}

@objc
class NotificationHapticFeedback: NSObject {
    let feedbackGenerator = UINotificationFeedbackGenerator()

    override init() {
        feedbackGenerator.prepare()
    }

    @objc
    func notificationOccurred(_ notificationType: UINotificationFeedbackGenerator.FeedbackType) {
        feedbackGenerator.notificationOccurred(notificationType)
        feedbackGenerator.prepare()
    }
}

@objc
class ImpactHapticFeedback: NSObject {
    @objc
    class func impactOccured(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}
