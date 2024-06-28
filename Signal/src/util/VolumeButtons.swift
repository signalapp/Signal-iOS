//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVKit
import MediaPlayer
import SignalServiceKit

protocol VolumeButtonObserver: AnyObject {

    /// On iOS versions greater than 17.2, an AVCaptureVideoPreviewLayer (which CapturePreviewView uses)
    /// must be on screen for volume button observation to work. Its size can be zero and/or alpha 0.01
    /// but it must be present and "visible". If it is not (or this value is nil) observers won't be updated.
    var capturePreviewView: CapturePreviewView? { get }

    func didPressVolumeButton(with identifier: VolumeButtons.Identifier)
    func didReleaseVolumeButton(with identifier: VolumeButtons.Identifier)

    func didTapVolumeButton(with identifier: VolumeButtons.Identifier)

    func didBeginLongPressVolumeButton(with identifier: VolumeButtons.Identifier)
    func didCompleteLongPressVolumeButton(with identifier: VolumeButtons.Identifier)
    func didCancelLongPressVolumeButton(with identifier: VolumeButtons.Identifier)
}

// Make the methods optional.

extension VolumeButtonObserver {
    func didPressVolumeButton(with identifier: VolumeButtons.Identifier) {}
    func didReleaseVolumeButton(with identifier: VolumeButtons.Identifier) {}

    func didTapVolumeButton(with identifier: VolumeButtons.Identifier) {}

    func didBeginLongPressVolumeButton(with identifier: VolumeButtons.Identifier) {}
    func didCompleteLongPressVolumeButton(with identifier: VolumeButtons.Identifier) {}
    func didCancelLongPressVolumeButton(with identifier: VolumeButtons.Identifier) {}
}

class VolumeButtons {
    static let shared = VolumeButtons()

    enum Identifier {
        case up, down
    }

    private init?() {
        // If for some reason the API we’re using goes away (for example, in
        // a future iOS version) this class will never instantiate.
        guard VolumeButtons.supportsListeningToEvents else { return nil }
    }

    deinit {
        stopObservation()
    }

    // MARK: - Volume Control

    // Odd as it is, the (easiest) way to set the system volume is via a
    // MPVolumeView, even if you never add it to any view hierarchy.
    private let volumeView = MPVolumeView()

    /// Incremenets the system volume, displaying the system UI when doing so.
    /// NOTE: this method is asynchronous (a limitation of somewhat illicit use of APIs), do not
    /// expect the volume to change immediately
    public func incrementSystemVolume(for identifier: Identifier) {
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.01) {
            var volume = AVAudioSession.sharedInstance().outputVolume
            let increment: Float = 1 / 16 // Number of increments apple uses.
            switch identifier {
            case .up:
                volume += increment
            case .down:
                volume -= increment
            }
            volume = min(1, max(0, volume))
            if volume == self.volumeView.slider?.value {
                // If setting the same value, set it _slightly_ off so the UI
                // shows up, then back to the actual desired value.
                var offset: Float = -0.01
                if volume == 0 {
                    offset = 0.01
                }
                self.volumeView.slider?.value = volume + offset
            }
            self.volumeView.slider?.value = volume
        }
    }

    // MARK: Observer Management

    private var observers: [Weak<VolumeButtonObserver>] = []
    func addObserver(observer: VolumeButtonObserver) {
        AssertIsOnMainThread()

        if observers.firstIndex(where: { $0.value === observer }) == nil {
            observers.append(Weak(value: observer))
        }

        guard !observers.isEmpty else { return }
        startObservation()
    }

    func removeObserver(_ observer: VolumeButtonObserver) {
        AssertIsOnMainThread()

        observers = observers.filter { $0.value !== observer }

        guard observers.isEmpty else { return }
        stopObservation()
    }

    private func startObservation() {
        guard !VolumeButtons.isRegisteredForEvents else { return }
        VolumeButtons.isRegisteredForEvents = true
        registerForNotifications()
    }

    private func stopObservation() {
        VolumeButtons.isRegisteredForEvents = false
        unregisterForNotifications()

        defer { resetLongPress() }
        guard let longPressingButton = longPressingButton else { return }
        notifyObserversOfCancelLongPress(with: longPressingButton)
    }

    private func notifyObserversOfTap(with identifier: Identifier) {
        observers.forEach { observer in
            observer.value?.didTapVolumeButton(with: identifier)
        }
    }

    private func notifyObserversOfBeginLongPress(with identifier: Identifier) {
        observers.forEach { observer in
            observer.value?.didBeginLongPressVolumeButton(with: identifier)
        }
    }

    private func notifyObserversOfCompleteLongPress(with identifier: Identifier) {
        observers.forEach { observer in
            observer.value?.didCompleteLongPressVolumeButton(with: identifier)
        }
    }

    private func notifyObserversOfCancelLongPress(with identifier: Identifier) {
        observers.forEach { observer in
            observer.value?.didCancelLongPressVolumeButton(with: identifier)
        }
    }

    private func notifyObserversOfPress(with identifier: Identifier) {
        observers.forEach { observer in
            observer.value?.didPressVolumeButton(with: identifier)
        }
    }

    private func notifyObserversOfRelease(with identifier: Identifier) {
        observers.forEach { observer in
            observer.value?.didReleaseVolumeButton(with: identifier)
        }
    }

    // MARK: Tap / long press handling

    private var longPressTimer: Timer?
    private var longPressingButton: Identifier?

    // It's not possible for up and down to be pressed simultaneously
    // (if you press the second button, the OS will end the press on
    // the first), so it allows for simplified handling here.
    private func didPressButton(with identifier: Identifier) {
        longPressingButton = nil

        longPressTimer?.invalidate()
        longPressTimer = WeakTimer.scheduledTimer(
            timeInterval: longPressDuration,
            target: self,
            userInfo: nil,
            repeats: false
        ) { [weak self] _ in
            self?.longPressingButton = identifier
            self?.notifyObserversOfBeginLongPress(with: identifier)
            self?.longPressTimer?.invalidate()
            self?.longPressTimer = nil
        }

        notifyObserversOfPress(with: identifier)
    }

    private func didReleaseButton(with identifier: Identifier) {
        if longPressingButton == identifier {
            notifyObserversOfCompleteLongPress(with: identifier)
        } else {
            notifyObserversOfTap(with: identifier)
        }

        resetLongPress()

        notifyObserversOfRelease(with: identifier)
    }

    private func resetLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressingButton = nil
    }

    // MARK: Volume Event Registration

    // let encodedSelectorString = "setWantsVolumeButtonEvents:".encodedForSelector
    private static let volumeEventsSelector = Selector("BXYGaHIABgVnAX0HfnZTBwYGAQBWCHYABgVL".decodedForSelector!)

    private(set) static var isRegisteredForEvents = false {
        didSet {
            setEventRegistration(isRegisteredForEvents)
        }
    }

    private static func setEventRegistration(_ active: Bool) {
        if #available(iOS 17.2, *) {
            return
        } else {
            typealias Type = @convention(c) (AnyObject, Selector, Bool) -> Void
            let implementation = class_getMethodImplementation(UIApplication.self, volumeEventsSelector)
            let setRegistration = unsafeBitCast(implementation, to: Type.self)
            setRegistration(UIApplication.shared, volumeEventsSelector, active)
        }
    }

    private static var supportsListeningToEvents: Bool {
        if #available(iOS 17.2, *) {
            return true
        } else {
            return UIApplication.shared.responds(to: volumeEventsSelector)
        }
    }

    // MARK: Notification Handling

    // let encodedDownDownNotificationName = "_UIApplicationVolumeDownButtonDownNotification".encodedForSelector
    private let downDownNotificationName = Notification.Name("cGZaUgICfXp0cgZ6AQBnAX0HfnZVAQkAUwcGBgEAVQEJAF8BBnp3enRyBnoBAA==".decodedForSelector!)

    // let encodedDownUpNotificationName = "_UIApplicationVolumeDownButtonUpNotification".encodedForSelector
    private let downUpNotificationName = Notification.Name("cGZaUgICfXp0cgZ6AQBnAX0HfnZVAQkAUwcGBgEAZgJfAQZ6d3p0cgZ6AQA=".decodedForSelector!)

    // let encodedUpDownNotificationName = "_UIApplicationVolumeUpButtonDownNotification".encodedForSelector
    private let upDownNotificationName = Notification.Name("cGZaUgICfXp0cgZ6AQBnAX0HfnZmAlMHBgYBAFUBCQBfAQZ6d3p0cgZ6AQA=".decodedForSelector!)

    // let encodedUpUpNotificationName = "_UIApplicationVolumeUpButtonUpNotification".encodedForSelector
    private let upUpNotificationName = Notification.Name("cGZaUgICfXp0cgZ6AQBnAX0HfnZmAlMHBgYBAGYCXwEGend6dHIGegEA".decodedForSelector!)

    private let longPressDuration: TimeInterval = 0.5

    // Stored properties can't have @available conditions;
    // store as Any and do casting in a computed var.
    private var _eventInteraction: Any?

    @available(iOS 17.2, *)
    private var eventInteraction: AVCaptureEventInteraction? {
        get { _eventInteraction as? AVCaptureEventInteraction }
        set { _eventInteraction = newValue }
    }

    private func registerForNotifications() {
        if #available(iOS 17.2, *) {
            let eventInteraction = AVCaptureEventInteraction(
                primary: { [weak self] volumeDownEvent in
                    switch volumeDownEvent.phase {
                    case .began:
                        self?.didPressVolumeDown()
                    case .ended:
                        self?.didReleaseVolumeDown()
                    case .cancelled:
                        fallthrough
                    @unknown default:
                        return
                    }
                },
                secondary: { [weak self] volumeUpEvent in
                    switch volumeUpEvent.phase {
                    case .began:
                        self?.didPressVolumeUp()
                    case .ended:
                        self?.didReleaseVolumeUp()
                    case .cancelled:
                        fallthrough
                    @unknown default:
                        return
                    }
                }
            )
            eventInteraction.isEnabled = true
            // TODO: someday, refactor this class to have an instance per-observer
            // rather than a global instance. Having one event interaction that is
            // added to multiple observers is not correct, but the global approach
            // was created for the pre-iOS 17.2 implementation below.
            observers.forEach { $0.value?.capturePreviewView?.addInteraction(eventInteraction) }
            self.eventInteraction = eventInteraction
        } else {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didPressVolumeUp),
                name: upDownNotificationName,
                object: nil
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didReleaseVolumeUp),
                name: upUpNotificationName,
                object: nil
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didPressVolumeDown),
                name: downDownNotificationName,
                object: nil
            )

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didReleaseVolumeDown),
                name: downUpNotificationName,
                object: nil
            )
        }
    }

    private func unregisterForNotifications() {
        if #available(iOS 17.2, *) {
            self.eventInteraction?.isEnabled = false
            if let eventInteraction {
                observers.forEach { $0.value?.capturePreviewView?.removeInteraction(eventInteraction) }
            }
            self.eventInteraction = nil
        } else {
            NotificationCenter.default.removeObserver(self)
        }
    }

    @objc
    private func didPressVolumeUp() {
        didPressButton(with: .up)
    }

    @objc
    private func didReleaseVolumeUp() {
        didReleaseButton(with: .up)
    }

    @objc
    private func didPressVolumeDown() {
        didPressButton(with: .down)
    }

    @objc
    private func didReleaseVolumeDown() {
        didReleaseButton(with: .down)
    }
}

fileprivate extension MPVolumeView {

    var slider: UISlider? {
        subviews.first(where: { $0 is UISlider }) as? UISlider
    }
}
