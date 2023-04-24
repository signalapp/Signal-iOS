//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

public class SelectionHapticFeedback {
    private let feedbackGenerator = UISelectionFeedbackGenerator()

    public init() {
        AssertIsOnMainThread()
        feedbackGenerator.prepare()
    }

    public func selectionChanged() {
        DispatchQueue.main.async {
            self.feedbackGenerator.selectionChanged()
            self.feedbackGenerator.prepare()
        }
    }
}

public class NotificationHapticFeedback {
    private let feedbackGenerator = UINotificationFeedbackGenerator()

    public init() {
        AssertIsOnMainThread()
        feedbackGenerator.prepare()
    }

    public func notificationOccurred(_ notificationType: UINotificationFeedbackGenerator.FeedbackType) {
        DispatchQueue.main.async {
            self.feedbackGenerator.notificationOccurred(notificationType)
            self.feedbackGenerator.prepare()
        }
    }
}

public class ImpactHapticFeedback {

    public class func impactOccurred(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }

    public class func impactOccurred(style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            if #available(iOS 13, *) {
                generator.impactOccurred(intensity: intensity)
            } else {
                generator.impactOccurred()
            }
        }
    }
}
