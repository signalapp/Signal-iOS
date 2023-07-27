//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Random number generation

// Generate a random float in the range [0.0f, 1.0f] using x, y, and z (based on the xor128 algorithm)
// Don't really care about "true" randomness; this is just used to generate particles so it just needs
// to be deterministic and look "random" to the human eye.
float rand(uint x, uint y, uint z)
{
    int seed = x + y * 57 + z * 241;
    seed= (seed<< 13) ^ seed;
    return (( 1.0 - ( (seed * (seed * seed * 15731 + 789221) + 1376312589) & 2147483647) / 1073741824.0f) + 1.0f) / 2.0f;
}


// MARK: - Swift<->C shared structs

/// **IMPORTANT**: these must be exactly identical to the values defined
/// in SpoilerParticleView.swift, as they are both schemas for interpreting
/// the same shared memory across the CPU (swift) and GPU (metal).

/// The GPU uses the elapsed time and rect position to create an RNG seed
/// to determine the actual particle positions deterministically on each tick.
/// This just contains metadata needed to draw each particle (a pointer to which
/// rect to draw it in).
/// For each one of these, the GPU will draw one little particle per layer.
/// (We do this to have less repeated information copied from CPU to GPU.)
struct ParticleSeed {
    /// Index in the provided draw rects array to draw this particle into.
    ushort drawRectIndex;
    /// Index of this particle in the draw rect. Serves as a unique identifier
    /// and part of the position random seeding.
    ushort indexInDrawRect;
};

/// A rectangle to draw particles into, represented in
/// the texture's coordinates.
struct DrawRect {
    // Note: these can be 16 bit because they are
    // in the texture's coordinates, which has
    // a max size of 
    ushort2 origin;
    ushort2 size;
    /// The color with which to draw particles in this rect.
    /// Values from 0 to 255. Note that textures use
    /// 0 to 1 half values for color; conversion is handled
    /// in the GPU.
    uchar3 particleRGB;
    /// The base alpha value for particle colors in this rect,
    /// with 255 representing an alpha of 1.
    uchar particleBaseAlpha;
    /// Every layer of particles has this much less alpha than the previous,
    /// with 255 representing an alpha of 1.
    uchar particleAlphaDropoff;
    /// The size (in texture coordinates) of particles in this rect.
    uchar particleSizePixels;
};

///  "Uniforms" is a term of art of data that is the same (uniform) across all parallel threads.
/// Contains information that applies to all particles we draw.
struct Uniforms {
    /// The amount of time passed since the animation started, in milliseconds.
    uint elapsedTimeMs;
    /// The number of particles seeds being rendered.
    /// This determines the max number of threads used
    /// and corresponds to the id value.
    uint numParticleSeeds;
    /// The number of layers to draw.
    /// We draw one particle per layer for each seed.
    uchar numParticleLayers;
};

// MARK: - Computation

/**
 * Runs every draw loop to clear the texture of the prior draw loop's values.
 *
 * **IMPORTANT**: the name of this function must be the same as the name used in
 * `MTLLibrary.makeFunction(name:)` in SpoilerParticleView.swift.
 */
kernel void clear_pass_func(texture2d<half, access::write> tex [[ texture(0) ]],
                            uint2 id [[ thread_position_in_grid ]]){
    // If the device doesn't support non-uniform thread groups, we
    // may end up with compute passes that extend past the edge of the grid.
    // Just early exit.
    if (id.x >= tex.get_width() || id.y >= tex.get_height()) {
        return;
    }
    tex.write(half4(0), id);
}

/**
 * Runs every draw loop, once per particle, in parallel across GPUs, drawing particles.
 *
 * **IMPORTANT**: the name of this function must be the same as the name used in
 * `MTLLibrary.makeFunction(name:)` in SpoilerParticleView.swift.
 *
 * Every particle gets its own run of this method in one "thread". Reading apple documentation
 * [here](https://developer.apple.com/documentation/metal/compute_passes/creating_threads_and_threadgroups) is recommended.
 * Basically a "thread" is a single computation that can be done in parallel. A "thread group" is a set of threads
 * that can all be run at the same time, the number depending on how many cores the GPU has. The "grid"
 * is the entire set of computation to run. Terminology is driven by image generation, where the "grid" is the 2D
 * grid of pixels, "thread groups" are blocks of pixels drawn in parallel, and "threads" are individual pixel draws.
 *
 * We use one thread per particle we draw, with ordering independent of its actual position. So visually you
 * can think of the "grid" as a 1d line with each slot being a pass to compute and draw a single particle, broken
 * up into thread group chunks of one particle per GPU core that we draw in parallel.
 *
 * Explaining the params' modifiers:
 *
 * `constant` means the GPU gets read access to that part of memory; another option
 * to keep in mind is `device`, which puts the data in shared device memory and lets
 * both the CPU and GPU read/write.
 *
 * The "[[ foo]]" stuff is annotation telling Metal where to get the parameter from.
 * `buffer(x)` refers to
 * the input MTLBuffers sent from swift with `MTLComputeCommandEncoder.setBuffer(..., index: x)`
 * with the given index.
 * `texture` is of course the texture being drawn to. We draw in 2d only, but textures can
 * be drawn onto 3d objects and you can have more than one of them.
 * `thread_position_in_grid` is the index of the thread in the entire set of threads. In our usage,
 * this is the index of the particle being drawn in the particles array.
 *
 * And the params themselves:
 * - parameter particleSeeds: A seed from which to generate particles, in other words the index
 * of the rect to draw it into, and an index _in_ that rect that serves to uniquely identify it from other seeds
 * in that rect). Indexed by `id`, with total capacity determined by the rect sizes and particle densities
 * (but we don't explicitly need it in here).
 * - parameter drawRects: The rects to draw into. They are uniquely identified by their origin.
 * - parameter uniforms: "Uniforms" is a term of art of data that is the same (uniform) across all
 * parallel threads. Stuff that is the same for all particles we are drawing.
 * - parameter id: Technically speaking, the thread's position in the grid. Serves as the index
 * into the particle array, since our "grid" is a 1d line of particles being drawn.
 */
kernel void draw_particles_func(constant ParticleSeed *particleSeeds [[ buffer(0) ]],
                                constant DrawRect *drawRects [[ buffer(1) ]],
                                constant Uniforms &uniforms [[ buffer(2) ]],
                                texture2d<half, access::write> tex [[ texture(0) ]],
                                uint id [[ thread_position_in_grid ]]){
    // If the device doesn't support non-uniform thread groups, we
    // may end up with more compute passes than we have particles.
    // Just early exit.
    if (id >= uniforms.numParticleSeeds) {
        return;
    }

    ParticleSeed particleSeed = particleSeeds[id];
    DrawRect rect = drawRects[particleSeed.drawRectIndex];

    // We encode these constant values here to avoid copying the memory from
    // cpu to gpu constantly.
    uint minParticleLifetimeMs = 1000;
    uint maxAdditionalParticleLifetimeMs = 2000;
    // Measured in pixels per ms.
    float maxParticleVelocity = 0.01;

    // Draw one particle per layer.
    for (uchar layer = 0; layer < uniforms.numParticleLayers; layer++) {

        // We are going to use some pseudo-random number generators to produce
        // the particle info (position, speed, etc) based a seed for each particle.
        // The seed has three parts:
        // 1. The draw rect's origin. These are unique and ensure we don't
        //    repeat particle patterns across rects.
        //
        // 2. The particle's index in the draw rect, plus an offset for its layer index.
        //    Basically, a unique id so its rng differs from other particles in the rect.
        //
        // 3. The current "reincarnation". Particles have a lifetime (determined by rng).
        //    After its reached, they die and "respawn" in a new random place. This is
        //    done by using the number of lifetimes as an input into the seed for position.
        //
        //    The particle lifetime is itself rng; so we first generate it randomly using the
        //    first two input seeds, then use that output to seed the rest.

        // First lets generate seed (2): we take the index in the rect, but offset by
        // the layer so each particle in each layer gets a unique seed.
        uint seedIndex = uint(particleSeed.indexInDrawRect) * uint(uniforms.numParticleLayers) + uint(layer);

        // Now we compute the lifetime and how many times we've reached it (seed (3)).
        float lifetimeRel = rand(rect.origin.x, rect.origin.y, seedIndex);
        uint lifetimeMs = uint(lifetimeRel * maxAdditionalParticleLifetimeMs) + minParticleLifetimeMs;
        uint numReincarnations = uniforms.elapsedTimeMs / lifetimeMs;
        uint durationInCurrentLifetime = uniforms.elapsedTimeMs - (lifetimeMs * numReincarnations);

        // Now we know the number of "reincarnations", and can seed the position
        // and velocity info.
        // We generate 4 numbers (x/y, position/velocity) for each particle,
        // so space out the "seed index" space by 4.
        // Then offset by 7 (can be any number, just not a multiple of 4)
        // for each lifetime so we get a new seed that doesn't overlap.
        seedIndex = seedIndex * 4 + (numReincarnations * 7);

        float xPosRel = rand(rect.origin.x, rect.origin.y, seedIndex);
        float yPosRel = rand(rect.origin.x, rect.origin.y, seedIndex + 1);
        float xVelRel = rand(rect.origin.x, rect.origin.y, seedIndex + 2);
        float yVelRel = rand(rect.origin.x, rect.origin.y, seedIndex + 3);

        // Positions are relative to the draw frame. compute final starting position.
        uint xPos = rect.origin.x + uint(xPosRel * rect.size.x);
        uint yPos = rect.origin.y + uint(yPosRel * rect.size.y);

        // Velocities are relative to the provided max velocity,
        // since it should be the same velocity distribution across rects.
        // Mininmum of half as much velocity, with positive or negative values.
        if (xVelRel > 0.5) {
            xPos += uint(xVelRel * maxParticleVelocity * durationInCurrentLifetime);
        } else {
            xPos -= uint((1 - xVelRel) * maxParticleVelocity * durationInCurrentLifetime);
        }
        if (yVelRel > 0.5) {
            yPos += uint(yVelRel * maxParticleVelocity * durationInCurrentLifetime);
        } else {
            yPos -= uint((1 - yVelRel) * maxParticleVelocity * durationInCurrentLifetime);
        }

        if(
           xPos < rect.origin.x
           || xPos > rect.origin.x + rect.size.x
           || yPos < rect.origin.y
           || yPos > rect.origin.y + rect.size.y
           ) {
               // If out of bounds, do not draw.
               return;
           }

        // Finally, draw the particles.

        // Compute the color, since the inputs are stuffed into
        // fewer bytes and we need them as floating point values.
        half r = half(rect.particleRGB.r) / 255;
        half g = half(rect.particleRGB.g) / 255;
        half b = half(rect.particleRGB.b) / 255;

        // alpha is dependent on the layer.
        half alpha = half(rect.particleBaseAlpha) / 255;
        half alphaDropoff = half(rect.particleAlphaDropoff) / 255;
        for (uchar i = 0; i < layer; i++) {
            alpha -= alphaDropoff;
        }
        half4 color = half4(r, g, b, alpha);

        // Figure out how many pixels we need to draw into.
        uint particleSize = uint(rect.particleSizePixels);
        uint topLeftOffset;
        uint bottomRightOffset;
        if (particleSize % 2 == 0) {
            topLeftOffset = particleSize / 2 - 1;
            bottomRightOffset = particleSize / 2;
        } else {
            topLeftOffset = (particleSize - 1) / 2;
            bottomRightOffset = (particleSize + 1) / 2 - 1;
        }

        // And draw.
        for(uint x = xPos - topLeftOffset; x <= xPos + bottomRightOffset; x++) {
            for(uint y = yPos - topLeftOffset; y <= yPos + bottomRightOffset; y++) {
                tex.write(color, uint2(x, y));
            }
        }
    }
}
