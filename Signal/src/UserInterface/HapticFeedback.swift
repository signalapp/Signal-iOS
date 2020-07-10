//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class SelectionHapticFeedback {
    let selectionFeedbackGenerator: UISelectionFeedbackGenerator

    init() {
        AssertIsOnMainThread()

        selectionFeedbackGenerator = UISelectionFeedbackGenerator()
        selectionFeedbackGenerator.prepare()
    }

    func selectionChanged() {
        DispatchQueue.main.async {
            self.selectionFeedbackGenerator.selectionChanged()
            self.selectionFeedbackGenerator.prepare()
        }
    }
}

@objc
class NotificationHapticFeedback: NSObject {
    let feedbackGenerator = UINotificationFeedbackGenerator()

    override init() {
        AssertIsOnMainThread()

        feedbackGenerator.prepare()
    }

    @objc
    func notificationOccurred(_ notificationType: UINotificationFeedbackGenerator.FeedbackType) {
        DispatchQueue.main.async {
            self.feedbackGenerator.notificationOccurred(notificationType)
            self.feedbackGenerator.prepare()
        }
    }
}

@objc
class ImpactHapticFeedback: NSObject {
    @objc
    class func impactOccured(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }
}
