//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public protocol SpoilerableViewAnimator {

    /// Nullable to enable holding a weak reference; it is assumed the view
    /// is deallocated when returning nil, and observation will be stopped.
    var spoilerableView: UIView? { get }
    var spoilerColor: UIColor { get }

    /// When the value of this key changes, the spoiler frames are recomputed.
    /// If it is unchanged, frames are assumed to also be unchanged and are reused.
    /// It is assumed computing frames is expensive, and computing the cache key is not.
    var spoilerFramesCacheKey: Int { get }

    func spoilerFrames() -> [CGRect]

    func equals(_ other: SpoilerableViewAnimator) -> Bool
}

extension SpoilerableViewAnimator {

    public func equals(_ other: SpoilerableViewAnimator) -> Bool {
        guard let view = self.spoilerableView, let otherView = other.spoilerableView else {
            return false
        }
        return view == otherView
    }
}

public class SpoilerAnimator {

    private let renderer: SpoilerRenderer

    public init() {
        let renderer = SpoilerRenderer()
        self.renderer = renderer
        self.tileImage = renderer.uiImage
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

    public func addViewAnimator(_ animator: SpoilerableViewAnimator) {
        animators.append(animator)
        redraw(animator: animator)
        startTimerIfNeeded()
    }

    public func removeViewAnimator(_ animator: SpoilerableViewAnimator) {
        removeTiles(animator: animator)
        animators.removeAll(where: {
            // Clear out nil view ones as well.
            $0.equals(animator) || $0.spoilerableView == nil
        })
        if animators.isEmpty {
            stopTimer()
        }
    }

    // MARK: - Observers

    private var animators: [SpoilerableViewAnimator] = []

    // Uniquely identifies the view.
    fileprivate class SpoilerTileView: UIView {}

    private func redraw(animator: SpoilerableViewAnimator) {
        guard FeatureFlags.spoilerAnimations else {
            return
        }

        guard let view = animator.spoilerableView else {
            return
        }

        let tilingColor = UIColor(patternImage: getOrLoadTileImage(animator: animator))

        let spoilerViews = view.subviews.filter { $0 is SpoilerTileView }
        let spoilerFrames = getOrLoadSpoilerFrames(animator: animator)
        for (i, rect) in spoilerFrames.enumerated() {
            let spoilerView: UIView = {
                if let existingView = spoilerViews[safe: i] {
                    return existingView
                } else {
                    // UIView and not a CALayer because of scrolling;
                    // CALayers aren't rendering properly when their parent
                    // is scrolling.
                    let spoilerView = SpoilerTileView()
                    view.addSubview(spoilerView)
                    spoilerView.layer.zPosition = .greatestFiniteMagnitude
                    return spoilerView
                }
            }()

            spoilerView.frame = rect
            spoilerView.backgroundColor = tilingColor
        }
        // Clear any excess layers.
        if spoilerViews.count > spoilerFrames.count {
            for i in spoilerFrames.count..<spoilerViews.count {
                spoilerViews[safe: i]?.removeFromSuperview()
            }
        }
    }

    private func removeTiles(animator: SpoilerableViewAnimator) {
        animator.spoilerableView?.subviews.forEach {
            if $0 is SpoilerTileView {
                $0.removeFromSuperview()
            }
        }
    }

    // MARK: - Caches

    private var frameCache = [Int: [CGRect]]()

    private func getOrLoadSpoilerFrames(animator: SpoilerableViewAnimator) -> [CGRect] {
        let cacheKey = animator.spoilerFramesCacheKey
        if let cachedFrames = frameCache[cacheKey] {
            return cachedFrames
        }
        let computedFrames = animator.spoilerFrames()
        frameCache[cacheKey] = computedFrames
        return computedFrames
    }

    private var tileImage: UIImage {
        didSet {
            tintedImageCache = [:]
        }
    }
    private var tintedImageCache = [UIColor: UIImage]()

    private func getOrLoadTileImage(animator: SpoilerableViewAnimator) -> UIImage {
        let color = animator.spoilerColor
        if let cachedImage = tintedImageCache[color] {
            return cachedImage
        }
        let tintedImage = tileImage.asTintedImage(color: color) ?? tileImage
        tintedImageCache[color] = tintedImage
        return tintedImage
    }

    // MARK: - Timer

    private var timer: Timer?

    private func startTimerIfNeeded() {
        guard FeatureFlags.spoilerAnimations else {
            return
        }
        guard timer == nil, animators.isEmpty.negated, UIAccessibility.isReduceMotionEnabled.negated else {
            return
        }
        renderer.resetLastDrawDate()
        let timer = Timer(timeInterval: 0.05, repeats: true, block: { [weak self] _ in
            self?.tick()
        })
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        self.tileImage = renderer.render()
        animators = animators.compactMap { animator in
            guard animator.spoilerableView != nil else {
                return nil
            }
            self.redraw(animator: animator)
            return animator
        }
        if animators.isEmpty {
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
