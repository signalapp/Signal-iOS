//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MetalKit
import SignalServiceKit

/// Information required to render with metal, that can be loaded once
/// on startup. If loading fails, we can fall back to non-animated spoiler
/// rendering.
public struct SpoilerMetalConfiguration {
    fileprivate var device: MTLDevice
    fileprivate var commandQueue: MTLCommandQueue
    fileprivate var clearPipelineState: MTLComputePipelineState
    fileprivate var drawParticlesPipelineState: MTLComputePipelineState

    fileprivate var supportsNonUniformThreadGroups: Bool

    /// The maximum width/height of a single texture (single ParticleView)
    /// supported by this device, in points.
    var maxTextureDimensionPoints: CGFloat

    public init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Logger.warn("Unable to instantiate metal device.")
            return nil
        }
        guard let commandQueue = device.makeCommandQueue() else {
            Logger.warn("Unable to instantiate metal command queue.")
            return nil
        }
        guard let library = device.makeDefaultLibrary() else {
            Logger.warn("Unable to instantiate metal library.")
            return nil
        }
        guard
            let clearFunc = library.makeFunction(name: "clear_pass_func"),
            let drawParticlesFunc = library.makeFunction(name: "draw_particles_func")
        else {
            Logger.warn("Unable to instantiate metal compute functions.")
            return nil
        }
        let clearPipelineState: MTLComputePipelineState
        let drawParticlesPipelineState: MTLComputePipelineState
        do {
            clearPipelineState = try device.makeComputePipelineState(function: clearFunc)
            drawParticlesPipelineState = try device.makeComputePipelineState(function: drawParticlesFunc)
        } catch {
            Logger.warn("Unable to instante metal compute pipelines: \(error)")
            return nil
        }
        self.device = device
        self.commandQueue = commandQueue
        self.clearPipelineState = clearPipelineState
        self.drawParticlesPipelineState = drawParticlesPipelineState

        self.supportsNonUniformThreadGroups = Self.getSupportsNonUniformThreadGroups(device)
        self.maxTextureDimensionPoints = Self.getMaxTextureDimensionPoints(device)
    }

    private static func getSupportsNonUniformThreadGroups(_ device: MTLDevice) -> Bool {
        // Taken from https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf
        // This whole this is extremely poorly documented. Hopefully if they release
        // a new GPU with e.g. .apple9, it will report itself as supporting .apple8
        // and such. MTLGPUFamily is not iterable, so there's not really anything
        // we can do here to guarantee forwards-compatibility.

        var knownGoodFamilies: [MTLGPUFamily] = [
            .common3,
            .apple4, .apple5, .apple6, .apple7, .apple8,
            .mac2
        ]
        if #available(iOS 16, *) {
            knownGoodFamilies.append(.metal3)
        }
        for knownGoodFamily in knownGoodFamilies {
            if device.supportsFamily(knownGoodFamily) {
                return true
            }
        }
        return false
    }

    private static func getMaxTextureDimensionPoints(_ device: MTLDevice) -> CGFloat {
        // Taken from https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf

        // NOTE: if this ever exceeds 32,767 (max 16-bit int) we need to update
        // the types in SpoilerParticleShader and corresponding structs in this file
        // to use 32-bit ints for positions.
        let pixelSize: CGFloat
        if device.supportsFamily(.apple3) {
            pixelSize = 16384
        } else if #available(iOS 16, *), device.supportsFamily(.mac2) {
            pixelSize = 16384
        } else {
            pixelSize = 8192
        }
        return pixelSize / UIScreen.main.scale
    }
}

internal class SpoilerParticleView: MTKView {

    private let metalConfig: SpoilerMetalConfiguration
    private let renderer: SpoilerRenderer

    init(
        metalConfig: SpoilerMetalConfiguration,
        renderer: SpoilerRenderer
    ) {
        self.metalConfig = metalConfig
        self.renderer = renderer
        super.init(frame: .zero, device: metalConfig.device)

        self.framebufferOnly = false
        self.preferredFramesPerSecond = Int(1 / Constants.defaultFrameDelay)
        layer.isOpaque = false
        // Start out paused until objects can be set.
        self.isPaused = true
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    private var spec: SpoilerRenderer.Spec?

    public func setSpec(_ spec: SpoilerRenderer.Spec) {
        self.spec = spec
    }

    /// Must be called after setting specs and view.frame information
    /// to generate metadata and be ready for rendering.
    func commitChanges() {
        prepareInputBuffersForMetal()
        setNeedsDisplay()
    }

    public var isInUse = false

    // MARK: - Swift<->C shared structs

    // IMPORTANT: these must be exactly identical to the values defined
    // in SpoilerParticleShader.metal, as they are both schemas for interpreting
    // the same shared memory across the CPU (swift) and GPU (metal).

    /// A rectangle to draw particles into, represented in
    /// the texture's coordinates.
    private struct DrawRect {
        var origin: SIMD2<UInt16>
        var size: SIMD2<UInt16>
        /// The color with which to draw particles in this rect.
        /// Values from 0 to 255. Note that textures use
        /// 0 to 1 half values for color; conversion is handled
        /// in the GPU.
        var particleRGB: SIMD3<UInt8>
        /// The base alpha value for particle colors in this rect,
        /// with 255 representing an alpha of 1.
        var particleBaseAlpha: UInt8
        /// Every layer of particles has this much less alpha than the previous,
        /// with 255 representing an alpha of 1.
        var particleAlphaDropoff: UInt8
        /// The size (in texture coordinates) of particles in this rect.
        var particleSizePixels: UInt8
    }

    ///  "Uniforms" is a term of art of data that is the same (uniform) across all parallel threads.
    /// Contains information that applies to all particles we draw.
    private struct Uniforms {
        /// The amount of time passed since the animation started, in milliseconds.
        var elapsedTimeMs: UInt32
        /// The number of rects being drawn into.
        var numDrawRects: UInt32
        /// The density of particles per pixel, per layer.
        /// In other words, in the texture's coordinates.
        var particlesPerPixelPerLayer: Float32
        /// The number of layers of particles to draw.
        var numLayers: UInt8
        /// Divisor for max particle speed.
        var particleSpeedDivisor: UInt8
    }

    private static let uniformsSize = MemoryLayout<Uniforms>.stride

    // MARK: - Metal Inputs

    private var frameDelay: CGFloat = Constants.defaultFrameDelay {
        didSet {
            self.preferredFramesPerSecond = Int(1 / frameDelay)
        }
    }
    private var numLayers: UInt8 = Constants.defaultNumLayers
    private var particleSpeedDivisor: UInt8 = Constants.defaultParticleSpeedDivisor
    private var particlesPerPixelPerLayer: Float32 = 0
    private var numDrawRects: UInt32 = 0
    private var drawRectBuffer: MTLBuffer?
    private var totalNumParticlesPerLayer: Int = 0

    private func resetMetalInputs() {
        frameDelay = Constants.defaultFrameDelay
        numLayers = Constants.defaultNumLayers
        particleSpeedDivisor = Constants.defaultParticleSpeedDivisor
        particlesPerPixelPerLayer = 0
        numDrawRects = 0
        drawRectBuffer = nil
        totalNumParticlesPerLayer = 0
        isPaused = true
    }

    func prepareInputBuffersForMetal() {
        guard bounds.width > 0, bounds.height > 0, let spec else {
            resetMetalInputs()
            return
        }
        var drawRects = [DrawRect]()

        let scale = UIScreen.main.scale

        var particlesPerUnitArea = Constants.defaultParticlesPerUnitArea

        var totalNumParticlesPerLayer = particlesPerUnitArea * spec.totalSurfaceArea
        if totalNumParticlesPerLayer > Constants.maxParticleCountPerLayer {
            particlesPerUnitArea *= Constants.maxParticleCountPerLayer / totalNumParticlesPerLayer
            totalNumParticlesPerLayer = Constants.maxParticleCountPerLayer
        }
        // Divide by scale sqaured because its 2d area.
        let particlesPerPixelPerLayer: CGFloat = particlesPerUnitArea / (scale * scale)

        var frameDelay = Constants.defaultFrameDelay
        var numLayers = Constants.defaultNumLayers
        var particleSpeedDivisor = Constants.defaultParticleSpeedDivisor
        if totalNumParticlesPerLayer > Constants.particleCountEfficiencyThreshold {
            frameDelay = Constants.efficientFrameDelay
            numLayers = Constants.efficientNumLayers
            particleSpeedDivisor = Constants.efficientParticleSpeedDivisor
        }

        owsAssertDebug(spec.spoilerFrames.count <= SpoilerAnimationManager.maxSpoilerFrameCount)
        for spoilerFrame in spec.spoilerFrames {
            guard
                spoilerFrame.frame.x >= bounds.x,
                spoilerFrame.frame.maxX <= bounds.maxX,
                spoilerFrame.frame.y >= bounds.y,
                spoilerFrame.frame.maxY <= bounds.maxY,
                spoilerFrame.frame.width > 0,
                spoilerFrame.frame.height > 0
            else {
                continue
            }
            let drawRect = DrawRect(
                origin: .init(
                    UInt16(clamping: UInt(spoilerFrame.frame.x * scale)),
                    UInt16(clamping: UInt(spoilerFrame.frame.y * scale))
                ),
                size: .init(
                    UInt16(clamping: UInt(spoilerFrame.frame.width * scale)),
                    UInt16(clamping: UInt(spoilerFrame.frame.height * scale))
                ),
                particleRGB: spoilerFrame.config.colorRGB,
                particleBaseAlpha: spoilerFrame.config.particleBaseAlpha,
                particleAlphaDropoff: spoilerFrame.config.particleAlphaDropoff,
                particleSizePixels: spoilerFrame.config.particleSizePixels
            )
            drawRects.append(drawRect)
        }

        guard drawRects.isEmpty.negated else {
            resetMetalInputs()
            return
        }

        self.particlesPerPixelPerLayer = Float32(particlesPerPixelPerLayer)
        self.numDrawRects = UInt32(clamping: drawRects.count)
        drawRectBuffer = metalConfig.device.makeBuffer(bytes: drawRects, length: MemoryLayout<DrawRect>.stride * drawRects.count)
        self.totalNumParticlesPerLayer = Int(totalNumParticlesPerLayer)

        self.frameDelay = frameDelay
        self.numLayers = numLayers
        self.particleSpeedDivisor = particleSpeedDivisor

        drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
        self.isPaused = false
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }
        // Need our state ready and committed before drawing.
        guard
            numDrawRects > 0,
            totalNumParticlesPerLayer > 0,
            let drawRectBuffer
        else {
            return
        }
        guard
            let drawable = self.currentDrawable,
            let commandbuffer = metalConfig.commandQueue.makeCommandBuffer(),
            let computeCommandEncoder = commandbuffer.makeComputeCommandEncoder()
        else {
            return
        }

        // First we apply the clear computation to the drawable's texture, wiping it
        // from whatever state it was in in the last draw cycle.
        computeCommandEncoder.setComputePipelineState(metalConfig.clearPipelineState)
        computeCommandEncoder.setTexture(drawable.texture, index: 0)

        // We have to figure out how to distribute the work among GPU cores.
        // `threadExecutionWidth` here is the number of GPU cores; a.k.a. the
        // number of things we can compute in parallel.
        // `maxTotalThreadsPerThreadgroup` is the number of instructions we can
        // send to a thread group at once to execute.
        // `h` is therefore how many things we will execute in serial in each group.
        let w = metalConfig.clearPipelineState.threadExecutionWidth
        let h = metalConfig.clearPipelineState.maxTotalThreadsPerThreadgroup / w

        // For the clear computation, we want each computation (each "thread") to wipe
        // one pixel. So we break it up into max-sized groups, and give it as many
        // threads as there are pixels in the texture.
        var threadsPerThreadGroup = MTLSize(width: w, height: h, depth: 1)
        var threadsPerGrid = MTLSize(width: drawable.texture.width, height: drawable.texture.height, depth: 1)

        if metalConfig.supportsNonUniformThreadGroups {
            // If the device supports it, we just provide group size and total number of threads, and
            // Metal will handle breaking up the grid into groups of variable size so we hit
            // every pixel without wasting any threads.
            computeCommandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        } else {
            // Otherwise we need to have a uniform thread group size, and since the total grid
            // size may not be a perfect multiple of the thread group size, we will have
            // wasted threads where the thread groups extend past the edge of the grid.
            let threadGroupsPerGrid = MTLSize(
                width: Int(ceil(Double(drawable.texture.width) / Double(w))),
                height: Int(ceil(Double(drawable.texture.height) / Double(h))),
                depth: 1
            )
            computeCommandEncoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        }

        // Now we actually draw the particles.
        computeCommandEncoder.setComputePipelineState(metalConfig.drawParticlesPipelineState)

        // Set the inputs we need. The indexing is important and must match
        // SpoilerParticleShader.metal.
        computeCommandEncoder.setBuffer(drawRectBuffer, offset: 0, index: 0)

        // The uniforms value (the current duration) is small and changes
        // on every draw loop. Its more efficient in these cases to use
        // setBytes to directly copy bytes and let Metal manage the memory.
        var uniforms = Uniforms(
            elapsedTimeMs: renderer.getAnimationDuration(),
            numDrawRects: numDrawRects,
            particlesPerPixelPerLayer: particlesPerPixelPerLayer,
            numLayers: numLayers,
            particleSpeedDivisor: particleSpeedDivisor
        )
        computeCommandEncoder.setBytes(&uniforms, length: Self.uniformsSize, index: 1)

        // For this computation, each "thread" will draw a single particle,
        // so we need as many threads as there are particles.
        // Grouping is not super important; treat it as a 1xn "grid".
        threadsPerGrid = MTLSize(width: totalNumParticlesPerLayer, height: 1, depth: 1)
        threadsPerThreadGroup = MTLSize(width: w, height: 1, depth: 1)
        if metalConfig.supportsNonUniformThreadGroups {
            // Same as above, use the more efficient method if available.
            computeCommandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        } else {
            // Otherwise use fixed group size that is likely too big.
            let threadGroupsPerGrid = MTLSize(
                width: Int(ceil(Double(totalNumParticlesPerLayer) / Double(w))),
                height: 1,
                depth: 1
            )
            computeCommandEncoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
        }

        // Tell the encoder we are done, and have it render the drawable's texture.
        computeCommandEncoder.endEncoding()
        #if targetEnvironment(simulator)
        commandbuffer.present(drawable)
        #else
        commandbuffer.present(drawable, afterMinimumDuration: frameDelay)
        #endif
        commandbuffer.commit()
    }

    fileprivate enum Constants {
        /// After this many particles, framerate, number of layers, and particle velocity degrade.
        static let particleCountEfficiencyThreshold: CGFloat = 1000
        /// Allow up to a maximum number of particles, to put an upper bound on compute.
        static let maxParticleCountPerLayer: CGFloat = 5000

        static let defaultFrameDelay: TimeInterval = 1/(20 /*FPS*/)
        static let efficientFrameDelay: TimeInterval = 1/(15 /*FPS*/)

        static let defaultParticleSpeedDivisor: UInt8 = 1
        static let efficientParticleSpeedDivisor: UInt8 = 2

        /// Number of particles per unit of surface area we render (per layer).
        /// If there's too much surface area to cover, the actual density may be lower,
        /// subject to max particle count limits.
        static let defaultParticlesPerUnitArea: CGFloat = 0.03
        static let efficientParticlesPerUnitArea: CGFloat = 0.01

        static let defaultNumLayers: UInt8 = 3
        static let efficientNumLayers: UInt8 = 2

        // Note that the particle max velocity, lifetime,
        // and number of layers are defined in
        // `SpoilerParticleShader.metal`, so we avoid copying
        // values from the CPU to the GPU.
    }
}
