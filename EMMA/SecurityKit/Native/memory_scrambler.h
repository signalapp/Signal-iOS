#ifndef EMMA_SECURITY_MEMORY_SCRAMBLER_H
#define EMMA_SECURITY_MEMORY_SCRAMBLER_H

#include <cstddef>
#include <cstdint>

namespace emma {
namespace security {

class MemoryScrambler {
public:
    // Securely wipe memory region (DoD 5220.22-M standard)
    static void secure_wipe(void* addr, size_t size);

    // Scramble memory with random data
    static void scramble_memory(void* addr, size_t size);

    // Fill all available RAM (for wiping sensitive data)
    // fill_percent: 0-100, percentage of available RAM to fill
    static void fill_available_ram(int fill_percent);

    // Create decoy memory patterns
    static void create_decoy_patterns(size_t size_mb);

private:
    // Helper to overwrite with pattern
    static void overwrite_with_pattern(void* addr, size_t size, uint8_t pattern);

    // Get available memory on iOS
    static size_t get_available_memory();
};

} // namespace security
} // namespace emma

#endif // EMMA_SECURITY_MEMORY_SCRAMBLER_H
