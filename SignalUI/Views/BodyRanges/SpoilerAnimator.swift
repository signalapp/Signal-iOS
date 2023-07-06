//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SpoilerAnimator {

    private let renderer = SpoilerRenderer()

    public init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterForeground),
            name: .OWSApplicationWillEnterForeground,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector:
                #selector(didEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector:
                #selector(reduceMotionSettingChanged),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func addObservingView(_ view: UIView) {
        let observer = Observer()
        observer.view = view
        observers.append(observer)
        observer.didUpdateSpoilerTile(renderer.uiImage)
        startTimerIfNeeded()
    }

    public func removeOvservingView(_ view: UIView) {
        observers.removeAll(where: { $0.view == view })
        if observers.isEmpty {
            stopTimer()
        }
    }

    // MARK: - Observers

    private class Observer {
        // TODO: these should refer to UILabels and UITextViews, once hooked up.
        weak var view: UIView?

        func didUpdateSpoilerTile(_ newTile: UIImage) {
            guard let view else { return }
            view.backgroundColor = .init(patternImage: newTile)
        }
    }

    private var observers: [Observer] = []

    // MARK: - Timer

    private var timer: Timer?

    func startTimerIfNeeded() {
        guard timer == nil, observers.isEmpty.negated, UIAccessibility.isReduceMotionEnabled.negated else {
            return
        }
        renderer.resetLastDrawDate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true, block: { [weak self] _ in
            self?.tick()
        })
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let newImage = renderer.render()
        observers = observers.compactMap { observer in
            guard observer.view != nil else {
                return nil
            }
            observer.didUpdateSpoilerTile(newImage)
            return observer
        }
        if observers.isEmpty {
            stopTimer()
        }
    }

    @objc
    private func didEnterForeground() {
        startTimerIfNeeded()
    }

    @objc
    private func didEnterBackground() {
        stopTimer()
    }

    @objc
    private func reduceMotionSettingChanged() {
        if UIAccessibility.isReduceMotionEnabled {
            stopTimer()
        } else {
            startTimerIfNeeded()
        }
    }
}
