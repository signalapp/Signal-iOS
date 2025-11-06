#include "memory_scrambler.h"
#include "../../Common/ios_platform.h"
#include <cstring>
#include <vector>
#include <sys/sysctl.h>
#include <mach/mach.h>

namespace emma {
namespace security {

void MemoryScrambler::secure_wipe(void* addr, size_t size) {
    if (!addr || size == 0) {
        return;
    }

    // DoD 5220.22-M standard: 3-pass overwrite
    // Pass 1: Write 0x00
    overwrite_with_pattern(addr, size, 0x00);

    // Pass 2: Write 0xFF
    overwrite_with_pattern(addr, size, 0xFF);

    // Pass 3: Write random data
    uint8_t* buffer = static_cast<uint8_t*>(addr);
    emma::platform::secure_random_bytes(buffer, size);

    // Final pass: Write zeros
    overwrite_with_pattern(addr, size, 0x00);

    // Ensure compiler doesn't optimize away the writes
    emma::platform::memory_barrier();
}

void MemoryScrambler::scramble_memory(void* addr, size_t size) {
    if (!addr || size == 0) {
        return;
    }

    uint8_t* buffer = static_cast<uint8_t*>(addr);
    emma::platform::secure_random_bytes(buffer, size);
    emma::platform::memory_barrier();
}

void MemoryScrambler::fill_available_ram(int fill_percent) {
    if (fill_percent < 0) fill_percent = 0;
    if (fill_percent > 100) fill_percent = 100;

    size_t available_memory = get_available_memory();
    size_t target_fill = (available_memory * fill_percent) / 100;

    EMMA_LOG_INFO("Filling %zu MB of RAM (%d%% of available)",
                  target_fill / (1024 * 1024), fill_percent);

    std::vector<std::vector<uint8_t>> allocations;

    try {
        size_t allocated = 0;
        constexpr size_t CHUNK_SIZE = 1024 * 1024; // 1 MB chunks

        while (allocated < target_fill) {
            size_t chunk_size = std::min(CHUNK_SIZE, target_fill - allocated);

            std::vector<uint8_t> chunk(chunk_size);
            emma::platform::secure_random_bytes(chunk.data(), chunk_size);

            // Touch every page to ensure allocation
            for (size_t i = 0; i < chunk_size; i += 4096) {
                chunk[i] = static_cast<uint8_t>(i & 0xFF);
            }

            allocations.push_back(std::move(chunk));
            allocated += chunk_size;
        }

        EMMA_LOG_INFO("Successfully allocated %zu MB", allocated / (1024 * 1024));

        // Keep allocations in memory for a short time
        // This forces iOS to page out other data
        for (auto& alloc : allocations) {
            volatile uint8_t dummy = alloc[0];
            (void)dummy;
        }

    } catch (const std::bad_alloc& e) {
        EMMA_LOG_ERROR("Memory allocation failed: %s", e.what());
    }

    // Allocations will be freed when vector goes out of scope
}

void MemoryScrambler::create_decoy_patterns(size_t size_mb) {
    size_t size_bytes = size_mb * 1024 * 1024;

    try {
        std::vector<uint8_t> decoy(size_bytes);

        // Create patterns that look like sensitive data
        for (size_t i = 0; i < size_bytes; i += 256) {
            // Pattern 1: Looks like encryption keys (random-ish)
            for (size_t j = 0; j < 32 && (i + j) < size_bytes; j++) {
                decoy[i + j] = static_cast<uint8_t>(rand() & 0xFF);
            }

            // Pattern 2: Looks like text data
            for (size_t j = 32; j < 128 && (i + j) < size_bytes; j++) {
                decoy[i + j] = static_cast<uint8_t>(0x20 + (rand() % 95)); // Printable ASCII
            }

            // Pattern 3: Looks like structured data
            for (size_t j = 128; j < 256 && (i + j) < size_bytes; j++) {
                decoy[i + j] = static_cast<uint8_t>((i + j) ^ 0xAA);
            }
        }

        // Touch all pages
        for (size_t i = 0; i < size_bytes; i += 4096) {
            volatile uint8_t dummy = decoy[i];
            (void)dummy;
        }

        EMMA_LOG_INFO("Created %zu MB of decoy patterns", size_mb);

    } catch (const std::bad_alloc& e) {
        EMMA_LOG_ERROR("Decoy pattern allocation failed: %s", e.what());
    }
}

void MemoryScrambler::overwrite_with_pattern(void* addr, size_t size, uint8_t pattern) {
    if (!addr || size == 0) {
        return;
    }

    volatile uint8_t* ptr = static_cast<volatile uint8_t*>(addr);

    for (size_t i = 0; i < size; i++) {
        ptr[i] = pattern;
    }
}

size_t MemoryScrambler::get_available_memory() {
    // Get available physical memory on iOS
    mach_port_t host_port = mach_host_self();
    mach_msg_type_number_t host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
    vm_size_t pagesize;
    vm_statistics_data_t vm_stat;

    host_page_size(host_port, &pagesize);

    if (host_statistics(host_port, HOST_VM_INFO,
                       (host_info_t)&vm_stat, &host_size) != KERN_SUCCESS) {
        EMMA_LOG_ERROR("Failed to get VM statistics");
        return 0;
    }

    // Available memory = free + inactive pages
    size_t available = (vm_stat.free_count + vm_stat.inactive_count) * pagesize;

    return available;
}

} // namespace security
} // namespace emma
