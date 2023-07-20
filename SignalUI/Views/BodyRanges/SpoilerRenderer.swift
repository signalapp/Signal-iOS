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

    private static let tileWidth: CGFloat = 100
    private static let xOverlayPercent: CGFloat = 0.10
    private static let tileHeight: CGFloat = 50
    private static let yOverlayPercent: CGFloat = 0.10

    /// When updated, sets the desired particles per unit, which will slowly
    /// transition existing particles to their final desired state by not respawning
    /// naturally despawned particles, and slowly spawning new particles each tick.
    ///
    /// This value is the number of particles in each particle set per unit area.
    /// So the total number of particles rendered will be:
    /// `particlesPerUnit * surfaceArea * numParticleSets`
    public var particlesPerUnit: CGFloat {
        get {
            return CGFloat(self.desiredParticlesPerSet) / (Self.tileWidth * Self.tileHeight)
        }
        set {
            self.desiredParticlesPerSet = Self.particleCount(particlesPerUnit: newValue)
        }
    }

    public var numParticleSets: Int {
        get {
            return desiredNumParticleSets
        }
        set {
            desiredNumParticleSets = newValue
        }
    }

    public var particleSpeedMultiplier: CGFloat = 1

    /// Disabled alpha values on particle colors, reducing performance costs.
    public var disableAlpha: Bool = false

    private static func particleCount(particlesPerUnit: CGFloat) -> Int {
        return Int(tileWidth * tileHeight * particlesPerUnit)
    }

    /// We render `numParticleSets` groups of particles,
    /// at different alphas, to enhance the visual effect.
    /// Each set has independent random motion.
    private lazy var particleSets: [[Particle]] = {
        var sets = [[Particle]]()
        for _ in 0..<desiredNumParticleSets {
            sets.append(.random(count: desiredParticlesPerSet))
        }
        return sets
    }()

    public struct Config: Hashable, Equatable {
        // The first particle set will have this alpha
        fileprivate let maxAlpha: CGFloat
        // Subsequent particle sets will reduce their alpha by this much.
        fileprivate let alphaDropoffRate: CGFloat
        fileprivate let particleRadiusPoints: CGFloat
        fileprivate let color: ThemedColor

        public static func standard(color: ThemedColor) -> Self {
            return .init(
                maxAlpha: 0.8,
                alphaDropoffRate: 0.1,
                particleRadiusPoints: 0.5,
                color: color
            )
        }

        public static func highlight(color: ThemedColor) -> Self {
            return .init(
                maxAlpha: 0.9,
                alphaDropoffRate: 0.05,
                particleRadiusPoints: 1,
                color: color
            )
        }

        fileprivate func alpha(forSetIndex index: Int) -> CGFloat {
            return max(0.1, maxAlpha - alphaDropoffRate * CGFloat(index))
        }
    }

    public struct Spec {
        public var frames: [CGRect]
        public var config: Config
    }

    public init(particlesPerUnit: CGFloat, numParticleSets: Int) {
        self.desiredParticlesPerSet = SpoilerRenderer.particleCount(particlesPerUnit: particlesPerUnit)
        self.desiredNumParticleSets = numParticleSets
    }

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
        return Self.getOrMakePattern(
            particleSets: particleSets,
            config: config,
            cache: &patternCache,
            disableAlpha: disableAlpha
        )
    }

    private static func getOrMakePattern(
        particleSets: [[Particle]],
        config: Config,
        cache: inout [Config: Pattern],
        disableAlpha: Bool
    ) -> Pattern? {
        if let cachedValue = cache[config] {
            return cachedValue
        }

        let patternSpecs = PatternSpecs(specs: (0..<particleSets.count).map { setIndex in
            let alpha = disableAlpha ? 1 : config.alpha(forSetIndex: setIndex)
            return PatternSpec(
                particles: particleSets[setIndex],
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

    private var desiredNumParticleSets: Int
    private var desiredParticlesPerSet: Int

    public func tick() {
        patternCache = [:]
        let now = Date()
        let timeDelta = now.timeIntervalSince(lastTickDate)
        lastTickDate = now

        let timeDeltaF = CGFloat(timeDelta)

        // Update particle positions.
        // Some particles will despawn (because they hit an edge,
        // or hit the end of their lifetime). If we are targeting
        // fewer particles than we have, let them die and remove them.
        // If not, respawn them.
        var particleIndexesToDespawn = [Int: [Int]]()
        for setIndex in 0..<particleSets.count {
            var currentParticleCount = particleSets[setIndex].count
            let desiredParticlesInSet: Int
            if setIndex > self.desiredNumParticleSets {
                desiredParticlesInSet = 0
            } else {
                desiredParticlesInSet = self.desiredParticlesPerSet
            }
            for particleIndex in 0..<particleSets[setIndex].count {
                var particle = particleSets[setIndex][particleIndex]
                defer {
                    particleSets[setIndex][particleIndex] = particle
                }
                let newX = particle.x + (timeDeltaF * particle.xVel * particleSpeedMultiplier)
                let newY = particle.y + (timeDeltaF * particle.yVel * particleSpeedMultiplier)
                let outOfBoundsX = newX < -Self.xOverlayPercent || newX > 1 + Self.xOverlayPercent
                let outOfBoundsY = newY < -Self.yOverlayPercent || newY > 1 + Self.yOverlayPercent
                particle.timeRemaining -= timeDelta * particleSpeedMultiplier
                if particle.timeRemaining < 0 || outOfBoundsX || outOfBoundsY {
                    if currentParticleCount > desiredParticlesInSet {
                        currentParticleCount -= 1
                        var indexesToDespawn = particleIndexesToDespawn[setIndex] ?? []
                        indexesToDespawn.append(particleIndex)
                        particleIndexesToDespawn[setIndex] = indexesToDespawn
                    } else {
                        particle.respawn()
                    }
                } else {
                    particle.x = newX
                    particle.y = newY
                }
            }
        }
        // Despawn any as needed.
        for (setIndex, particleIndexes) in particleIndexesToDespawn {
            var particleSet = particleSets[setIndex]
            for particleIndex in particleIndexes.reversed() {
                particleSet.remove(at: particleIndex)
            }
            particleSets[setIndex] = particleSet
        }
        // Spawn new ones as needed.
        for setIndex in 0..<desiredNumParticleSets {
            var particleSet = particleSets[safe: setIndex] ?? []
            // Only spawn up to 5 particles per tick.
            var particlesToSpawn = max(5, desiredParticlesPerSet - particleSet.count)
            while particlesToSpawn > 0 {
                particleSet.append(Particle.random())
                particlesToSpawn -= 1
            }
            if self.particleSets.count <= setIndex {
                self.particleSets.append(particleSet)
            } else {
                particleSets[setIndex] = particleSet
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
