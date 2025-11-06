#ifndef EMMA_IOS_PLATFORM_H
#define EMMA_IOS_PLATFORM_H

// iOS Platform Definitions for EMMA Security
// Replaces Android-specific headers with iOS equivalents

#include <os/log.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <sys/sysctl.h>
#include <Security/Security.h>
#include <cstdint>
#include <cstddef>

namespace emma {
namespace platform {

// iOS Logging (replaces Android log)
extern os_log_t emma_log;

#define EMMA_LOG_DEBUG(fmt, ...) os_log_debug(emma::platform::emma_log, fmt, ##__VA_ARGS__)
#define EMMA_LOG_INFO(fmt, ...) os_log_info(emma::platform::emma_log, fmt, ##__VA_ARGS__)
#define EMMA_LOG_ERROR(fmt, ...) os_log_error(emma::platform::emma_log, fmt, ##__VA_ARGS__)

// iOS Secure Random (replaces /dev/urandom)
inline bool secure_random_bytes(uint8_t* buffer, size_t size) {
    return SecRandomCopyBytes(kSecRandomDefault, size, buffer) == errSecSuccess;
}

// High-resolution timestamp (works on iOS ARM64)
inline uint64_t read_timestamp_counter() {
    uint64_t val;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r" (val));
    return val;
}

// Get timestamp frequency
inline uint64_t get_timestamp_frequency() {
    uint64_t freq;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r" (freq));
    return freq;
}

// Cache operations (ARM64 - compatible with both Android and iOS)
inline void flush_cache_line(void* addr) {
    __asm__ volatile("dc civac, %0" : : "r" (addr) : "memory");
}

inline void prefetch_cache_line(void* addr) {
    __asm__ volatile("prfm pldl1keep, [%0]" : : "r" (addr));
}

// Memory barrier
inline void memory_barrier() {
    __asm__ volatile("dmb sy" : : : "memory");
}

} // namespace platform
} // namespace emma

#endif // EMMA_IOS_PLATFORM_H
