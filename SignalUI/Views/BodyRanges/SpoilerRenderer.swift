//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Produces the actual particle effects used to tile spoilered regions.
/// Does not on its own animate or apply any spoiler animations; `SpoilerAnimationManager`
/// handles that. Instead this class just produces one tile, one frame at a time, and applies them
/// as custom sublayers on UIViews
public class SpoilerRenderer {

    /// Should these vary by device? Or drop when getting a memory warning?
    /// Performance is sensitive to these values. Tweak them if it becomes an issue.
    private static let tileWidth: CGFloat = 100
    private static let xOverlayPercent: CGFloat = 0.10
    private static let tileHeight: CGFloat = 50
    private static let yOverlayPercent: CGFloat = 0.10
    private static let particlesPerUnit: CGFloat = 0.04

    private static let particleCount = Int(tileWidth * tileHeight * particlesPerUnit)

    // Must be three sets in sync with the config below.
    // We render 3 groups of particles, at different alphas, to enhance
    // the visual effect. Each has independent random motion.
    private lazy var particleSets: [[Particle]] = [
        .random(count: Self.particleCount),
        .random(count: Self.particleCount),
        .random(count: Self.particleCount)
    ]

    public struct Config: Hashable, Equatable {
        // Must be three alpha values, for the three particle sets.
        // constructors for this config are private for this reason.
        fileprivate let particleAlphas: [CGFloat]
        fileprivate let particleRadiusPoints: CGFloat
        fileprivate let color: ThemedColor

        public static func standard(color: ThemedColor) -> Self {
            return .init(particleAlphas: [0.8, 0.7, 0.6], particleRadiusPoints: 0.5, color: color)
        }

        public static func highlight(color: ThemedColor) -> Self {
            return .init(particleAlphas: [0.9, 0.85, 0.8], particleRadiusPoints: 1, color: color)
        }
    }

    public struct Spec {
        public var frames: [CGRect]
        public var config: Config
    }

    public init() {}

    public func render(_ specs: [Spec], onto view: UIView) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var existingLayers: [ParticleLayer] = view.layer.sublayers?.compactMap { $0 as? ParticleLayer } ?? []
        for spec in specs {
            let particleLayer: ParticleLayer
            if existingLayers.isEmpty.negated {
                particleLayer = existingLayers.remove(at: 0)
            } else {
                particleLayer = ParticleLayer()
                particleLayer.frame = view.bounds
                view.layer.addSublayer(particleLayer)
            }
            particleLayer.pattern = getOrMakePattern(config: spec.config)
            particleLayer.frames = spec.frames
            particleLayer.frame = view.bounds
            particleLayer.setNeedsDisplay()
        }
        // Remove any extras.
        existingLayers.forEach { $0.removeFromSuperlayer() }
        CATransaction.commit()
    }

    public static func removeSpoilerLayers(from view: UIView) {
        view.layer.sublayers?.forEach {
            ($0 as? ParticleLayer)?.removeFromSuperlayer()
        }
    }

    // MARK: - Pattern Generation

    private class PatternSpec {
        let particles: [Particle]
        let radius: CGFloat
        let color: CGColor

        init(particles: [Particle], radius: CGFloat, color: CGColor) {
            self.particles = particles
            self.radius = radius
            self.color = color
        }
    }

    /// We cannot pass a simple array of PatternSpecs as the info param on CGPattern;
    /// arrays are structs and break when used as unsafe mutable pointers.
    /// Instead wrap the array in a class type so the pointer remains stable.
    private class PatternSpecs {
        let specs: [PatternSpec]

        init(specs: [PatternSpec]) {
            self.specs = specs
        }
    }

    private class Pattern {
        // CGPattern holds unsafe pointers to each of these;
        // we need to retain them so the pointer address remains stable.
        private var specs: PatternSpecs
        private var callbacks: CGPatternCallbacks

        let pattern: CGPattern

        init?(specs: PatternSpecs) {
            self.specs = specs

            self.callbacks = CGPatternCallbacks.init(
                version: 0,
                drawPattern: { info, context in
                    guard let patternSpecs = info?.load(as: PatternSpecs.self) else {
                        return
                    }
                    for patternSpec in patternSpecs.specs {
                        context.setFillColor(patternSpec.color)
                        let size = patternSpec.radius * 2
                        context.fill(patternSpec.particles.compactMap { particle in
                            return CGRect(
                                x: particle.x * SpoilerRenderer.tileWidth - patternSpec.radius,
                                y: particle.y * SpoilerRenderer.tileHeight - patternSpec.radius,
                                width: size,
                                height: size
                            )
                        })
                    }
                },
                releaseInfo: nil
            )

            guard let pattern = CGPattern(
                info: &self.specs,
                bounds: CGRect(x: 0, y: 0, width: SpoilerRenderer.tileWidth, height: SpoilerRenderer.tileHeight),
                matrix: .identity,
                xStep: SpoilerRenderer.tileWidth,
                yStep: SpoilerRenderer.tileHeight,
                tiling: .constantSpacing,
                isColored: true,
                callbacks: &self.callbacks
            ) else {
                return nil
            }
            self.pattern = pattern
        }
    }

    private var patternCache = [Config: Pattern]()

    private func getOrMakePattern(config: Config) -> Pattern? {
        return Self.getOrMakePattern(particleSets: particleSets, config: config, cache: &patternCache)
    }

    private static func getOrMakePattern(
        particleSets: [[Particle]],
        config: Config,
        cache: inout [Config: Pattern]
    ) -> Pattern? {
        if let cachedValue = cache[config] {
            return cachedValue
        }

        let patternSpecs = PatternSpecs(specs: config.particleAlphas.enumerated().map { index, alpha in
            return PatternSpec(
                particles: particleSets[index],
                radius: config.particleRadiusPoints,
                color: config.color.forCurrentTheme.withAlphaComponent(alpha).cgColor
            )
        })

        guard let pattern = Pattern(specs: patternSpecs) else {
            return nil
        }

        cache[config] = pattern
        return pattern
    }

    // MARK: - ParticleLayer

    private class ParticleLayer: CALayer {
        var pattern: Pattern?
        var frames: [CGRect]?

        override init() {
            super.init()
            super.contentsScale = UIScreen.main.scale
        }

        override init(layer: Any) {
            super.init(layer: layer)
            super.contentsScale = UIScreen.main.scale

            guard let particleLayer = layer as? ParticleLayer else {
                return
            }
            self.pattern = particleLayer.pattern
            self.frames = particleLayer.frames
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public override func draw(in context: CGContext) {
            guard let pattern, let frames else {
                return
            }

            guard context.width > 0, context.height > 0 else {
                return
            }

            guard let patternSpace = CGColorSpace(patternBaseSpace: nil) else {
                return
            }
            context.setFillColorSpace(patternSpace)

            var alpha: CGFloat = 1
            context.setFillPattern(pattern.pattern, colorComponents: &alpha)
            context.fill(frames)
        }
    }

    // MARK: - Ticking Time (updating particle positions)

    private var lastTickDate = Date()

    public func resetLastTickDate() {
        self.lastTickDate = Date()
    }

    public func tick() {
        patternCache = [:]
        let now = Date()
        let timeDelta = now.timeIntervalSince(lastTickDate)
        lastTickDate = now

        let timeDeltaF = CGFloat(timeDelta)

        for setIndex in 0..<particleSets.count {
            for particleIndex in 0..<particleSets[setIndex].count {
                var particle = particleSets[setIndex][particleIndex]
                defer {
                    particleSets[setIndex][particleIndex] = particle
                }
                let newX = particle.x + (timeDeltaF * particle.xVel)
                let newY = particle.y + (timeDeltaF * particle.yVel)
                let outOfBoundsX = newX < -Self.xOverlayPercent || newX > 1 + Self.xOverlayPercent
                let outOfBoundsY = newY < -Self.yOverlayPercent || newY > 1 + Self.yOverlayPercent
                particle.timeRemaining -= timeDelta
                if particle.timeRemaining < 0 || outOfBoundsX || outOfBoundsY {
                    particle.respawn()
                } else {
                    particle.x = newX
                    particle.y = newY
                }
            }
        }
    }

    fileprivate struct Particle {
        // Values from 0 to 1 representing percentage
        // of position across the tile
        var x: CGFloat
        var y: CGFloat
        // Values representing percent of tile dimension
        // moved per second. e.g. 1 = moves tile width in 1 second.
        var xVel: CGFloat
        var yVel: CGFloat
        // Time until the particle disappears.
        var timeRemaining: TimeInterval

        static func random() -> Particle {
            return .init(
                x: .random(in: -SpoilerRenderer.xOverlayPercent...(1 + SpoilerRenderer.xOverlayPercent)),
                y: .random(in: -SpoilerRenderer.yOverlayPercent...(1 + SpoilerRenderer.yOverlayPercent)),
                xVel: .random(in: -0.1...0.1),
                // Y is faster than X because absolute height is smaller.
                yVel: .random(in: -0.2...0.2),
                timeRemaining: .random(in: 1...2)
            )
        }

        mutating func respawn() {
            x = .random(in: -SpoilerRenderer.xOverlayPercent...(1 + SpoilerRenderer.xOverlayPercent))
            y = .random(in: -SpoilerRenderer.yOverlayPercent...(1 + SpoilerRenderer.yOverlayPercent))
            xVel = .random(in: -0.1...0.1)
            // Y is faster than X because absolute height is smaller.
            yVel = .random(in: -0.2...0.2)
            timeRemaining = .random(in: 1...2)
        }
    }
}

extension Array where Element == SpoilerRenderer.Particle {

    static func random(count: Int) -> Self {
        return (0..<count).map { _ in .random() }
    }
}
