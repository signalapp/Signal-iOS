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

    private let renderer = SpoilerRenderer(
        particlesPerUnit: SpoilerAnimationManager.highDensityParticlesPerUnit,
        numParticleSets: SpoilerAnimationManager.highDensityNumParticleSets
    )

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
        _ = redraw(animator: animator)
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

    private func redraw(animator: SpoilerableViewAnimator) -> SurfaceArea {
        guard FeatureFlags.spoilerAnimations else {
            return 0
        }

        guard let view = animator.spoilerableView else {
            return 0
        }

        let (specs, surfaceArea) = getOrLoadSpoilerSpecs(animator: animator)
        renderer.render(specs, onto: view)
        return surfaceArea
    }

    // MARK: - Caches

    // Computing frames is expensive. Doing it for every tick of animation, for
    // every bit of text shown on screen, adds up.
    // To avoid this, we cache the last computed frame, and rely on animators
    // to provide a cache key (which should be cheap to compute) to determine
    // when we should discard the cache and recompute frames.
    private var specCache = [Int: ([SpoilerRenderer.Spec], SurfaceArea)]()

    private func getOrLoadSpoilerSpecs(animator: SpoilerableViewAnimator) -> ([SpoilerRenderer.Spec], SurfaceArea) {
        let cacheKey = animator.spoilerFramesCacheKey
        if let cachedFrames = specCache[cacheKey] {
            return cachedFrames
        }
        let computedFrames = animator.spoilerFrames()
        var surfaceArea: SurfaceArea = 0
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
            surfaceArea += frame.frame.width * frame.frame.height
            var colorSpecs = specs[color] ?? [:]
            colorSpecs[style] = spec
            specs[color] = colorSpecs
        }
        let finalSpecs: [SpoilerRenderer.Spec] = specs.values.flatMap(\.values)
        specCache[cacheKey] = (finalSpecs, surfaceArea)
        return (finalSpecs, surfaceArea)
    }

    // MARK: - Performance Degradation

    typealias SurfaceArea = CGFloat

    /// Once we hit this much total surface area being used to render spoilers, we lower fidelity
    /// to improve performance.
    private static let surfaceAreaThreshold: SurfaceArea = 200 * 200

    private static let highFramerate: Double = 20 // fps
    private static let lowFramerate: Double = 15 // fps

    private static let highDensityNumParticleSets = 3
    private static let lowDensityNumParticleSets = 2

    private static let highDensityParticlesPerUnit = 0.04
    private static let lowDensityParticlesPerUnit = 0.02

    private var isHighFidelity = true

    // MARK: - Timer

    private var tickInterval: TimeInterval {
        if isHighFidelity {
            return 1 / Self.highFramerate
        } else {
            return 1 / Self.lowFramerate
        }
    }

    private var timer: Timer?

    private func startTimerIfNeeded() {
        guard FeatureFlags.spoilerAnimations else {
            return
        }
        guard timer == nil, animators.isEmpty.negated, UIAccessibility.isReduceMotionEnabled.negated else {
            return
        }
        renderer.resetLastTickDate()
        let timer = Timer(timeInterval: tickInterval, repeats: true, block: { [weak self] _ in
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
        var totalSurfaceArea: SurfaceArea = 0
        animators = animators.compactMap { animator in
            guard animator.spoilerableView != nil else {
                return nil
            }
            totalSurfaceArea += self.redraw(animator: animator)
            return animator
        }
        if animators.isEmpty {
            stopTimer()
        }
        let shouldBeHighFidelity = totalSurfaceArea < Self.surfaceAreaThreshold
        if shouldBeHighFidelity != isHighFidelity {
            stopTimer()
            self.isHighFidelity = shouldBeHighFidelity
            if shouldBeHighFidelity {
                renderer.particlesPerUnit = Self.highDensityParticlesPerUnit
                renderer.numParticleSets = Self.highDensityNumParticleSets
            } else {
                renderer.particlesPerUnit = Self.lowDensityParticlesPerUnit
                renderer.numParticleSets = Self.lowDensityNumParticleSets
            }
            startTimerIfNeeded()
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
