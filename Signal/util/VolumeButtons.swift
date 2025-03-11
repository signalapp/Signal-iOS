//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVKit
import MediaPlayer
import SignalServiceKit

protocol PassiveVolumeButtonObserver: AnyObject {

    /// Does not say which volume button was tapped (because we may not know),
    /// just that the system volume was changed by tapping one of the buttons.
    /// Observing this does _not_ override the default volume button behavior.
    func didTapSomeVolumeButton()
}

class PassiveVolumeButtonObservation {

    private weak var observer: PassiveVolumeButtonObserver?

    public init(observer: PassiveVolumeButtonObserver) {
        self.observer = observer
        if #available(iOS 17.2, *) {
            beginObservation()
        } else {
            beginLegacyObservation()
        }
    }

    deinit {
        if #available(iOS 17.2, *) {
            stopObservation()
        } else {
            stopLegacyObservation()
        }
    }

    // let encodedUpUpNotificationName = "SystemVolumeDidChange".encodedForSelector
    private let volumeChangeNotificationName = Notification.Name("ZAsFBnZ+ZwF9B352VXp1VHlyAHh2".decodedForSelector!)

    /// Without an MPVolumeView (or, maybe, its usage of the private class MPVolumeControllerSystemDataSource)
    /// instance in memory, SystemVolumeDidChange notifications are not fired.
    private var volumeViewForObservation: MPVolumeView?

    @available(iOS 17.2, *)
    private func beginObservation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemVolumeDidChange(_:)),
            name: volumeChangeNotificationName,
            object: nil
        )
        volumeViewForObservation = MPVolumeView()
    }

    private func beginLegacyObservation() {
        LegacyGlobalVolumeButtonObserver.shared?.addObserver(observer: self)
    }

    @available(iOS 17.2, *)
    private func stopObservation() {
        NotificationCenter.default.removeObserver(self)
        volumeViewForObservation = nil
    }

    private func stopLegacyObservation() {
        LegacyGlobalVolumeButtonObserver.shared?.removeObserver(self)
    }

    @objc
    private func systemVolumeDidChange(_ notification: NSNotification) {
        guard notification.userInfo?["Reason"] as? String == "ExplicitVolumeChange" else {
            return
        }
        didTapSomeVolumeButton()
    }

    fileprivate func didTapSomeVolumeButton() {
        observer?.didTapSomeVolumeButton()
    }
}

// Namespace for types and constants
enum VolumeButtons {
    enum Identifier {
        case up, down
    }

    fileprivate static let longPressDuration: TimeInterval = 0.5
}

protocol AVVolumeButtonObserver: AnyObject {

    func didPressVolumeButton(with identifier: VolumeButtons.Identifier)
    func didReleaseVolumeButton(with identifier: VolumeButtons.Identifier)

    func didTapVolumeButton(with identifier: VolumeButtons.Identifier)

    func didBeginLongPressVolumeButton(with identifier: VolumeButtons.Identifier)
    func didCompleteLongPressVolumeButton(with identifier: VolumeButtons.Identifier)
    func didCancelLongPressVolumeButton(with identifier: VolumeButtons.Identifier)
}

class AVVolumeButtonObservation {

    private weak var observer: AVVolumeButtonObserver?
    private weak var capturePreviewView: CapturePreviewView?

    public var isEnabled = true {
        didSet {
            if #available(iOS 17.2, *) {
                eventInteraction?.isEnabled = isEnabled
            } else {
                if isEnabled && !oldValue {
                    beginLegacyObservation()
                } else if !isEnabled && oldValue {
                    stopLegacyObservation()
                }
            }
        }
    }

    /// On iOS versions greater than 17.2, an AVCaptureVideoPreviewLayer (which CapturePreviewView uses)
    /// must be on screen for volume button observation to work. Its size can be zero and/or alpha 0.01
    /// but it must be present and "visible". If it is not observers won't be updated.
    public init(observer: AVVolumeButtonObserver, capturePreviewView: CapturePreviewView) {
        self.observer = observer
        self.capturePreviewView = capturePreviewView

        if #available(iOS 17.2, *) {
            beginObservation()
        } else {
            beginLegacyObservation()
        }
    }

    deinit {
        if #available(iOS 17.2, *) {
            stopObservation()
        } else {
            stopLegacyObservation()
        }
    }

    // Stored properties can't have @available conditions;
    // store as Any and do casting in a computed var.
    private var _eventInteraction: Any?

    @available(iOS 17.2, *)
    private var eventInteraction: AVCaptureEventInteraction? {
        get { _eventInteraction as? AVCaptureEventInteraction }
        set { _eventInteraction = newValue }
    }

    @available(iOS 17.2, *)
    private func beginObservation() {
        let eventInteraction = AVCaptureEventInteraction(
            primary: { [weak self] volumeDownEvent in
                switch volumeDownEvent.phase {
                case .began:
                    self?.didPressVolumeButton(with: .down)
                case .ended:
                    self?.didReleaseVolumeButton(with: .down)
                case .cancelled:
                    fallthrough
                @unknown default:
                    return
                }
            },
            secondary: { [weak self] volumeUpEvent in
                switch volumeUpEvent.phase {
                case .began:
                    self?.didPressVolumeButton(with: .up)
                case .ended:
                    self?.didReleaseVolumeButton(with: .up)
                case .cancelled:
                    fallthrough
                @unknown default:
                    return
                }
            }
        )
        eventInteraction.isEnabled = isEnabled
        capturePreviewView?.addInteraction(eventInteraction)
        self.eventInteraction = eventInteraction
    }

    private func beginLegacyObservation() {
        LegacyGlobalVolumeButtonObserver.shared?.addObserver(observer: self)
    }

    @available(iOS 17.2, *)
    private func stopObservation() {
        self.eventInteraction?.isEnabled = false
        if let eventInteraction {
            capturePreviewView?.removeInteraction(eventInteraction)
        }
        self.eventInteraction = nil

        if let longPressingButton {
            observer?.didCancelLongPressVolumeButton(with: longPressingButton)
            resetLongPress()
        }
    }

    private func stopLegacyObservation() {
        LegacyGlobalVolumeButtonObserver.shared?.removeObserver(self)

        if let longPressingButton {
            observer?.didCancelLongPressVolumeButton(with: longPressingButton)
            resetLongPress()
        }
    }

    // MARK: Tap / long press handling

    private var longPressTimer: Timer?
    private var longPressingButton: VolumeButtons.Identifier?

    // It's not possible for up and down to be pressed simultaneously
    // (if you press the second button, the OS will end the press on
    // the first), so it allows for simplified handling here.
    fileprivate func didPressVolumeButton(with identifier: VolumeButtons.Identifier) {
        longPressingButton = nil

        longPressTimer?.invalidate()
        longPressTimer = WeakTimer.scheduledTimer(
            timeInterval: VolumeButtons.longPressDuration,
            target: self,
            userInfo: nil,
            repeats: false
        ) { [weak self] _ in
            self?.longPressingButton = identifier
            self?.observer?.didBeginLongPressVolumeButton(with: identifier)
            self?.longPressTimer?.invalidate()
            self?.longPressTimer = nil
        }

        observer?.didPressVolumeButton(with: identifier)
    }

    fileprivate func didReleaseVolumeButton(with identifier: VolumeButtons.Identifier) {
        if longPressingButton == identifier {
            observer?.didCompleteLongPressVolumeButton(with: identifier)
        } else {
            observer?.didTapVolumeButton(with: identifier)
        }

        resetLongPress()

        observer?.didReleaseVolumeButton(with: identifier)
    }

    private func resetLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        longPressingButton = nil
    }
}

// MARK: - Legacy

private protocol LegacyVolumeButtonObserver: AnyObject {

    func didPressVolumeButton(with identifier: VolumeButtons.Identifier)
    func didReleaseVolumeButton(with identifier: VolumeButtons.Identifier)
}

extension AVVolumeButtonObservation: LegacyVolumeButtonObserver {}

extension PassiveVolumeButtonObservation: LegacyVolumeButtonObserver {

    func didPressVolumeButton(with identifier: VolumeButtons.Identifier) {
        // We _don't_ want to interrupt the system from changing the volume
        LegacyGlobalVolumeButtonObserver.shared?.incrementSystemVolume(for: identifier)

        didTapSomeVolumeButton()
    }

    func didReleaseVolumeButton(with identifier: VolumeButtons.Identifier) {
        // We _don't_ want to interrupt the system from changing the volume
        LegacyGlobalVolumeButtonObserver.shared?.incrementSystemVolume(for: identifier)

        didTapSomeVolumeButton()
    }
}

// MARK: - Legacy Global observer

private class LegacyGlobalVolumeButtonObserver {
    static let shared = LegacyGlobalVolumeButtonObserver()

    fileprivate init?() {
        if #available(iOS 17.2, *) {
            // Should NOT be used after iOS 17.2
            return nil
        }
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
    public func incrementSystemVolume(for identifier: VolumeButtons.Identifier) {
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

    private var observers: [Weak<LegacyVolumeButtonObserver>] = []
    func addObserver(observer: LegacyVolumeButtonObserver) {
        AssertIsOnMainThread()

        if observers.firstIndex(where: { $0.value === observer }) == nil {
            observers.append(Weak(value: observer))
        }

        guard !observers.isEmpty else { return }
        startObservation()
    }

    func removeObserver(_ observer: LegacyVolumeButtonObserver) {
        AssertIsOnMainThread()

        observers = observers.filter { $0.value !== observer }

        guard observers.isEmpty else { return }
        stopObservation()
    }

    private func startObservation() {
        guard !Self.isRegisteredForEvents else { return }
        Self.isRegisteredForEvents = true
        registerForNotifications()
    }

    private func stopObservation() {
        Self.isRegisteredForEvents = false
        unregisterForNotifications()
    }

    private func notifyObserversOfPress(with identifier: VolumeButtons.Identifier) {
        observers.forEach { observer in
            observer.value?.didPressVolumeButton(with: identifier)
        }
    }

    private func notifyObserversOfRelease(with identifier: VolumeButtons.Identifier) {
        observers.forEach { observer in
            observer.value?.didReleaseVolumeButton(with: identifier)
        }
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
        typealias Type = @convention(c) (AnyObject, Selector, Bool) -> Void
        let implementation = class_getMethodImplementation(UIApplication.self, volumeEventsSelector)
        let setRegistration = unsafeBitCast(implementation, to: Type.self)
        setRegistration(UIApplication.shared, volumeEventsSelector, active)
    }

    private static var supportsListeningToEvents: Bool {
        return UIApplication.shared.responds(to: volumeEventsSelector)
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

    private func registerForNotifications() {
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

    private func unregisterForNotifications() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    private func didPressVolumeUp() {
        notifyObserversOfPress(with: .up)
    }

    @objc
    private func didReleaseVolumeUp() {
        notifyObserversOfRelease(with: .up)
    }

    @objc
    private func didPressVolumeDown() {
        notifyObserversOfPress(with: .down)
    }

    @objc
    private func didReleaseVolumeDown() {
        notifyObserversOfRelease(with: .down)
    }
}

fileprivate extension MPVolumeView {

    var slider: UISlider? {
        subviews.first(where: { $0 is UISlider }) as? UISlider
    }
}
