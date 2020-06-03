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

@objc
enum NotificationHapticFeedbackType: Int {
    case error, success, warning
}

@available(iOS 10.0, *)
extension NotificationHapticFeedbackType {
    var uiNotificationFeedbackType: UINotificationFeedbackGenerator.FeedbackType {
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

@objc
class NotificationHapticFeedback: NSObject, NotificationHapticFeedbackAdapter {

    let adapter: NotificationHapticFeedbackAdapter

    override init() {
        if #available(iOS 10, *) {
            adapter = ModernNotificationHapticFeedbackAdapter()
        } else {
            adapter = LegacyNotificationHapticFeedbackAdapter()
        }
    }

    @objc
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

protocol ImpactHapticFeedbackAdapter {
    func impactOccurred()
}

@objc
class ImpactHapticFeedback: NSObject, ImpactHapticFeedbackAdapter {
    let adapter: ImpactHapticFeedbackAdapter

    @objc
    override init() {
        if #available(iOS 10, *) {
            adapter = ModernImpactHapticFeedbackAdapter()
        } else {
            adapter = LegacyImpactHapticFeedbackAdapter()
        }
    }

    @objc
    func impactOccurred() {
        adapter.impactOccurred()
    }
}

class LegacyImpactHapticFeedbackAdapter: NSObject, ImpactHapticFeedbackAdapter {
    func impactOccurred() {
        // do nothing
    }
}

@available(iOS 10, *)
class ModernImpactHapticFeedbackAdapter: NSObject, ImpactHapticFeedbackAdapter {
    let impactFeedbackGenerator: UIImpactFeedbackGenerator

    override init() {
        impactFeedbackGenerator = UIImpactFeedbackGenerator()
        impactFeedbackGenerator.prepare()
    }

    // MARK: HapticAdapter

    func impactOccurred() {
        impactFeedbackGenerator.impactOccurred()
        impactFeedbackGenerator.prepare()
    }
}
