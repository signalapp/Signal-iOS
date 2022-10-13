//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SelectionHapticFeedback {
    let selectionFeedbackGenerator: UISelectionFeedbackGenerator

    public init() {
        AssertIsOnMainThread()

        selectionFeedbackGenerator = UISelectionFeedbackGenerator()
        selectionFeedbackGenerator.prepare()
    }

    public func selectionChanged() {
        DispatchQueue.main.async {
            self.selectionFeedbackGenerator.selectionChanged()
            self.selectionFeedbackGenerator.prepare()
        }
    }
}

@objc
public class NotificationHapticFeedback: NSObject {
    let feedbackGenerator = UINotificationFeedbackGenerator()

    public override init() {
        AssertIsOnMainThread()

        feedbackGenerator.prepare()
    }

    @objc
    public func notificationOccurred(_ notificationType: UINotificationFeedbackGenerator.FeedbackType) {
        DispatchQueue.main.async {
            self.feedbackGenerator.notificationOccurred(notificationType)
            self.feedbackGenerator.prepare()
        }
    }
}

@objc
public class ImpactHapticFeedback: NSObject {
    @objc
    public class func impactOccured(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }

    @objc
    public class func impactOccured(style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
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
