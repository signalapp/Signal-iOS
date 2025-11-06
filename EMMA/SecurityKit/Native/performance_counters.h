#ifndef EMMA_SECURITY_PERFORMANCE_COUNTERS_H
#define EMMA_SECURITY_PERFORMANCE_COUNTERS_H

// iOS-adapted Performance Counters
// Note: iOS does not provide direct access to hardware performance counters
// like Linux perf_event_open. This implementation uses available iOS APIs.

#include <cstdint>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <sys/types.h>
#include <vector>

namespace emma {
namespace security {

struct PerfCounterData {
    uint64_t cycles;              // Estimated from mach_absolute_time
    uint64_t instructions;        // Not directly available on iOS (estimated)
    uint64_t cache_references;    // Not directly available (estimated)
    uint64_t cache_misses;        // Not directly available (estimated)
    uint64_t branch_instructions; // Not directly available (estimated)
    uint64_t branch_misses;       // Not directly available (estimated)
    uint64_t context_switches;    // Available via task_info
    uint64_t cpu_migrations;      // Estimated via thread info

    // iOS-specific additional data
    uint64_t resident_size;       // Memory resident size
    uint64_t virtual_size;        // Virtual memory size
    uint32_t thread_count;        // Number of threads
};

class PerformanceCounters {
public:
    PerformanceCounters();
    ~PerformanceCounters();

    bool initialize();
    bool read_counters(PerfCounterData& data);
    void close_counters();

    // Check if performance counters are available
    // On iOS, this checks if we can read basic metrics
    bool are_counters_accessible();

private:
    // iOS-specific implementations
    bool read_task_info(task_vm_info_data_t& info);
    bool read_thread_basic_info(thread_basic_info_data_t& info);
    uint64_t estimate_instructions();
    uint64_t estimate_cache_references();
    uint64_t estimate_cache_misses();

    mach_port_t task_;
    mach_timebase_info_data_t timebase_;
    bool initialized_;

    // Baseline measurements for estimation
    uint64_t baseline_time_;
    uint64_t baseline_cycles_;
    task_vm_info_data_t baseline_vm_info_;
};

} // namespace security
} // namespace emma

#endif // EMMA_SECURITY_PERFORMANCE_COUNTERS_H
