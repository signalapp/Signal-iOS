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

enum NotificationHapticFeedbackType {
    case error, success, warning
}

extension NotificationHapticFeedbackType {
    var uiNotificationFeedbackType: UINotificationFeedbackType {
        switch self {
        case .error: return .error
        case .success: return .success
        case .warning: return .warning
        }
    }
}

protocol NotificationHapticFeedbackAdapter {
    func notificationOccurred(_ notificationType: NotificationHapticFeedbackType)
}

class NotificationHapticFeedback: NotificationHapticFeedbackAdapter {

    let adapter: NotificationHapticFeedbackAdapter

    init() {
        if #available(iOS 10, *) {
            adapter = ModernNotificationHapticFeedbackAdapter()
        } else {
            adapter = LegacyNotificationHapticFeedbackAdapter()
        }
    }

    func notificationOccurred(_ notificationType: NotificationHapticFeedbackType) {
        adapter.notificationOccurred(notificationType)
    }
}

@available(iOS 10.0, *)
class ModernNotificationHapticFeedbackAdapter: NotificationHapticFeedbackAdapter {
    let feedbackGenerator = UINotificationFeedbackGenerator()

    init() {
        feedbackGenerator.prepare()
    }

    func notificationOccurred(_ notificationType: NotificationHapticFeedbackType) {
        feedbackGenerator.notificationOccurred(notificationType.uiNotificationFeedbackType)
        feedbackGenerator.prepare()
    }
}

class LegacyNotificationHapticFeedbackAdapter: NotificationHapticFeedbackAdapter {
    func notificationOccurred(_ notificationType: NotificationHapticFeedbackType) {
        vibrate()
    }

    private func vibrate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
}
