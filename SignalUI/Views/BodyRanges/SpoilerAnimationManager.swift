//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// A single rectangle in which to render spoilers.
public struct SpoilerFrame {

    public enum Style: Int {
        /// Fade effect, small particles
        case standard
        /// More solid, larger particles.
        case highlight
    }

    public let frame: CGRect
    public let color: ThemedColor
    public let style: Style

    public init(frame: CGRect, color: ThemedColor, style: Style) {
        self.frame = frame
        self.color = color
        self.style = style
    }
}

/// Conform to this to provide spoiler information (the view to apply spoilers to,
/// the frames of the spoilers, etc) to a `SpoilerableViewAnimator`.
///
/// The UIView itself can conform to `SpoilerableViewAnimator`, but this is
/// not necessarily the case. This flexibility allows using any UIView class for
/// spoiler application, and defining a separate animator, without having to subclass
/// the UIView class in question.
public protocol SpoilerableViewAnimator {

    /// Nullable to enable holding a weak reference; it is assumed the view
    /// is deallocated when returning nil, and observation will be stopped.
    var spoilerableView: UIView? { get }

    /// When the value of this key changes, the spoiler frames are recomputed.
    /// If it is unchanged, frames are assumed to also be unchanged and are reused.
    /// It is assumed computing frames is expensive, and computing the cache key is not.
    var spoilerFramesCacheKey: Int { get }

    func spoilerFrames() -> [SpoilerFrame]

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

/// Manages the animations of spoilers on views provided by `SpoilerableViewAnimator`.
/// As long as there is a spoiler to render, ticks time to re-render spoiler particles produced by
/// `SpoilerRenderer`.
/// Stops consuming resources if there are no spoilers to render.
///
/// Sharing an animation manager as much as possible is recommended. This reduces resources by
/// reusing the same rendered spoiler tiles across all views on the same animation manager.
public class SpoilerAnimationManager {

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

    public func addViewAnimator(_ animator: SpoilerableViewAnimator) {
        animators.append(animator)
        redraw(animator: animator)
        startTimerIfNeeded()
    }

    public func removeViewAnimator(_ animator: SpoilerableViewAnimator) {
        animator.spoilerableView.map(SpoilerRenderer.removeSpoilerLayers(from:))
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

    private func redraw(animator: SpoilerableViewAnimator) {
        guard FeatureFlags.spoilerAnimations else {
            return
        }

        guard let view = animator.spoilerableView else {
            return
        }

        let specs = getOrLoadSpoilerSpecs(animator: animator)
        renderer.render(specs, onto: view)
    }

    // MARK: - Caches

    // Computing frames is expensive. Doing it for every tick of animation, for
    // every bit of text shown on screen, adds up.
    // To avoid this, we cache the last computed frame, and rely on animators
    // to provide a cache key (which should be cheap to compute) to determine
    // when we should discard the cache and recompute frames.
    private var specCache = [Int: [SpoilerRenderer.Spec]]()

    private func getOrLoadSpoilerSpecs(animator: SpoilerableViewAnimator) -> [SpoilerRenderer.Spec] {
        let cacheKey = animator.spoilerFramesCacheKey
        if let cachedFrames = specCache[cacheKey] {
            return cachedFrames
        }
        let computedFrames = animator.spoilerFrames()
        var specs = [ThemedColor: [SpoilerFrame.Style: SpoilerRenderer.Spec]]()
        for frame in computedFrames {
            let color = frame.color
            let style = frame.style
            var spec: SpoilerRenderer.Spec = specs[color]?[style] ?? {
                switch style {
                case .standard: return .init(frames: [], config: .standard(color: color))
                case .highlight: return .init(frames: [], config: .highlight(color: color))
                }
            }()
            spec.frames.append(frame.frame)
            var colorSpecs = specs[color] ?? [:]
            colorSpecs[style] = spec
            specs[color] = colorSpecs
        }
        let finalSpecs: [SpoilerRenderer.Spec] = specs.values.flatMap(\.values)
        specCache[cacheKey] = finalSpecs
        return finalSpecs
    }

    // MARK: - Timer

    private static let tickInterval: TimeInterval = 0.05

    private var timer: Timer?

    private func startTimerIfNeeded() {
        guard FeatureFlags.spoilerAnimations else {
            return
        }
        guard timer == nil, animators.isEmpty.negated, UIAccessibility.isReduceMotionEnabled.negated else {
            return
        }
        renderer.resetLastTickDate()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true, block: { [weak self] _ in
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
        renderer.tick()
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
