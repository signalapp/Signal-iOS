#ifndef EMMA_SECURITY_CACHE_OPERATIONS_H
#define EMMA_SECURITY_CACHE_OPERATIONS_H

#include <cstddef>
#include <cstdint>

namespace emma {
namespace security {

class CacheOperations {
public:
    // Cache poisoning to disrupt side-channel attacks
    static void poison_cache(int intensity_percent);

    // Flush specific cache range
    static void flush_cache_range(void* addr, size_t size);

    // Prefetch cache range (for obfuscation)
    static void prefetch_cache_range(void* addr, size_t size);

    // Fill cache with noise
    static void fill_cache_with_noise(size_t size_kb);

private:
    // Low-level cache operations
    static void flush_cache_line(void* addr);
    static void prefetch_cache_line(void* addr);
};

} // namespace security
} // namespace emma

#endif // EMMA_SECURITY_CACHE_OPERATIONS_H
