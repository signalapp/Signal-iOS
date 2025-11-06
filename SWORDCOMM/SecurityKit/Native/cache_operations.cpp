#include "cache_operations.h"
#include "../../Common/ios_platform.h"
#include <vector>
#include <cstring>
#include <stdlib.h>

namespace emma {
namespace security {

void CacheOperations::poison_cache(int intensity_percent) {
    if (intensity_percent < 0) intensity_percent = 0;
    if (intensity_percent > 100) intensity_percent = 100;

    // Calculate size based on intensity
    // Assume L1 cache ~64KB, L2 ~4MB, L3 ~8MB per core
    // Intensity 100% = fill ~8MB
    size_t cache_size_kb = (8 * 1024 * intensity_percent) / 100;

    if (cache_size_kb > 0) {
        fill_cache_with_noise(cache_size_kb);
    }

    SWORDCOMM_LOG_DEBUG("Cache poisoned with intensity %d%%", intensity_percent);
}

void CacheOperations::flush_cache_range(void* addr, size_t size) {
    if (!addr || size == 0) {
        return;
    }

    // Flush cache lines in the range
    // ARM64 cache line size is typically 64 bytes
    constexpr size_t CACHE_LINE_SIZE = 64;

    uintptr_t start = reinterpret_cast<uintptr_t>(addr);
    uintptr_t end = start + size;

    // Align to cache line boundaries
    start = start & ~(CACHE_LINE_SIZE - 1);

    for (uintptr_t ptr = start; ptr < end; ptr += CACHE_LINE_SIZE) {
        flush_cache_line(reinterpret_cast<void*>(ptr));
    }

    emma::platform::memory_barrier();
}

void CacheOperations::prefetch_cache_range(void* addr, size_t size) {
    if (!addr || size == 0) {
        return;
    }

    constexpr size_t CACHE_LINE_SIZE = 64;

    uintptr_t start = reinterpret_cast<uintptr_t>(addr);
    uintptr_t end = start + size;

    start = start & ~(CACHE_LINE_SIZE - 1);

    for (uintptr_t ptr = start; ptr < end; ptr += CACHE_LINE_SIZE) {
        prefetch_cache_line(reinterpret_cast<void*>(ptr));
    }

    emma::platform::memory_barrier();
}

void CacheOperations::fill_cache_with_noise(size_t size_kb) {
    size_t size_bytes = size_kb * 1024;

    // Allocate noise buffer
    std::vector<uint8_t> noise(size_bytes);

    // Fill with random data
    if (!emma::platform::secure_random_bytes(noise.data(), size_bytes)) {
        SWORDCOMM_LOG_ERROR("Failed to generate random noise for cache fill");
        return;
    }

    // Touch every cache line to bring into cache
    constexpr size_t CACHE_LINE_SIZE = 64;
    volatile uint8_t dummy = 0;

    for (size_t i = 0; i < size_bytes; i += CACHE_LINE_SIZE) {
        dummy += noise[i]; // Force read
    }

    // Prefetch to ensure data is in cache
    prefetch_cache_range(noise.data(), size_bytes);

    SWORDCOMM_LOG_DEBUG("Filled cache with %zu KB of noise", size_kb);
}

void CacheOperations::flush_cache_line(void* addr) {
    // ARM64 cache flush instruction
    emma::platform::flush_cache_line(addr);
}

void CacheOperations::prefetch_cache_line(void* addr) {
    // ARM64 cache prefetch instruction
    emma::platform::prefetch_cache_line(addr);
}

} // namespace security
} // namespace emma
