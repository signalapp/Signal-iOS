#include "el2_detector.h"
#include "cache_operations.h"
#include "../../Common/ios_platform.h"
#include <cstring>
#include <cmath>
#include <vector>
#include <sys/sysctl.h>
#include <dlfcn.h>

namespace emma {
namespace security {

EL2Detector::EL2Detector()
    : initialized_(false)
    , last_analysis_time_(0)
    , consecutive_detections_(0) {
    std::memset(&baseline_, 0, sizeof(baseline_));
}

EL2Detector::~EL2Detector() {
}

bool EL2Detector::initialize() {
    if (initialized_) {
        return true;
    }

    // Initialize performance counters
    if (!perf_counters_.initialize()) {
        EMMA_LOG_ERROR("Failed to initialize performance counters");
        return false;
    }

    // Establish baseline measurements
    establish_baseline();

    initialized_ = true;
    last_analysis_time_ = rdtsc();

    EMMA_LOG_INFO("EL2 Detector initialized successfully");
    return true;
}

ThreatAnalysis EL2Detector::analyze_threat() {
    ThreatAnalysis analysis;
    std::memset(&analysis, 0, sizeof(analysis));

    if (!initialized_) {
        EMMA_LOG_ERROR("EL2 Detector not initialized");
        analysis.threat_level = 0.0f;
        return analysis;
    }

    // Run all detection methods
    float timing_score = detect_timing_anomalies();
    float cache_score = detect_cache_anomalies();
    float perf_counter_score = detect_perf_counter_blocking();
    float memory_score = detect_memory_anomalies();

    // iOS-specific detections
    float jailbreak_score = detect_jailbreak_indicators();
    float debugger_score = detect_debugger_attachment();
    float codesign_score = detect_code_signing_tampering();

    // Populate analysis structure
    analysis.timing_anomaly_detected = (timing_score > 0.5f);
    analysis.cache_anomaly_detected = (cache_score > 0.5f);
    analysis.perf_counter_blocked = (perf_counter_score > 0.5f);
    analysis.memory_anomaly_detected = (memory_score > 0.5f);

    // Calculate overall threat level (weighted average)
    analysis.threat_level = (
        timing_score * 0.20f +
        cache_score * 0.20f +
        perf_counter_score * 0.15f +
        memory_score * 0.15f +
        jailbreak_score * 0.15f +
        debugger_score * 0.10f +
        codesign_score * 0.05f
    );

    // Clamp to 0.0-1.0
    if (analysis.threat_level > 1.0f) analysis.threat_level = 1.0f;
    if (analysis.threat_level < 0.0f) analysis.threat_level = 0.0f;

    // Calculate hypervisor confidence
    // On iOS, this is more about jailbreak/debugging than hypervisor
    analysis.hypervisor_confidence = (jailbreak_score + debugger_score) / 2.0f;

    analysis.analysis_timestamp = rdtsc();

    // Track consecutive detections
    if (analysis.threat_level > 0.7f) {
        consecutive_detections_++;
    } else {
        consecutive_detections_ = 0;
    }

    EMMA_LOG_DEBUG("Threat analysis: level=%.2f, hypervisor=%.2f, timing=%d, cache=%d",
                   analysis.threat_level, analysis.hypervisor_confidence,
                   analysis.timing_anomaly_detected, analysis.cache_anomaly_detected);

    last_analysis_time_ = rdtsc();

    return analysis;
}

void EL2Detector::establish_baseline() {
    constexpr int NUM_SAMPLES = 10;

    double total_cache_latency = 0.0;
    double total_instruction_latency = 0.0;
    double total_cpi = 0.0;
    double total_cache_miss_rate = 0.0;

    // Allocate test buffer for cache measurements
    constexpr size_t TEST_SIZE = 1024 * 1024; // 1 MB
    std::vector<uint8_t> test_buffer(TEST_SIZE);

    for (int i = 0; i < NUM_SAMPLES; i++) {
        // Measure cache latency
        uint64_t start = rdtsc();
        cache_probe(test_buffer.data(), TEST_SIZE);
        uint64_t end = rdtsc();
        total_cache_latency += (end - start);

        // Measure instruction latency
        start = rdtsc();
        volatile int dummy = 0;
        for (int j = 0; j < 1000; j++) {
            dummy += j;
        }
        end = rdtsc();
        total_instruction_latency += (end - start);

        // Read performance counters
        PerfCounterData perf;
        if (perf_counters_.read_counters(perf)) {
            if (perf.instructions > 0) {
                total_cpi += static_cast<double>(perf.cycles) / perf.instructions;
            }

            if (perf.cache_references > 0) {
                total_cache_miss_rate += static_cast<double>(perf.cache_misses) / perf.cache_references;
            }
        }

        // Small delay between samples
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }

    baseline_.avg_cache_latency = total_cache_latency / NUM_SAMPLES;
    baseline_.avg_instruction_latency = total_instruction_latency / NUM_SAMPLES;
    baseline_.avg_cycles_per_instruction = total_cpi / NUM_SAMPLES;
    baseline_.avg_cache_miss_rate = total_cache_miss_rate / NUM_SAMPLES;
    baseline_.baseline_timestamp = rdtsc();

    EMMA_LOG_INFO("Baseline established: cache_lat=%.2f, inst_lat=%.2f, cpi=%.4f, miss_rate=%.4f",
                  baseline_.avg_cache_latency,
                  baseline_.avg_instruction_latency,
                  baseline_.avg_cycles_per_instruction,
                  baseline_.avg_cache_miss_rate);
}

float EL2Detector::detect_timing_anomalies() {
    constexpr int NUM_TESTS = 5;
    int anomalies = 0;

    for (int i = 0; i < NUM_TESTS; i++) {
        uint64_t start = rdtsc();

        // Simple operation
        volatile int dummy = 0;
        for (int j = 0; j < 1000; j++) {
            dummy += j;
        }

        uint64_t end = rdtsc();
        double latency = static_cast<double>(end - start);

        // Check if significantly different from baseline
        double deviation = std::abs(latency - baseline_.avg_instruction_latency) / baseline_.avg_instruction_latency;

        if (deviation > 0.5) { // 50% deviation threshold
            anomalies++;
        }
    }

    return static_cast<float>(anomalies) / NUM_TESTS;
}

float EL2Detector::detect_cache_anomalies() {
    constexpr size_t TEST_SIZE = 64 * 1024; // 64 KB
    std::vector<uint8_t> test_buffer(TEST_SIZE);

    // Warm up cache
    cache_probe(test_buffer.data(), TEST_SIZE);

    // Measure cached access time
    uint64_t start = rdtsc();
    cache_probe(test_buffer.data(), TEST_SIZE);
    uint64_t end = rdtsc();

    double cached_latency = static_cast<double>(end - start);

    // Flush cache and measure uncached access
    cache_flush(test_buffer.data(), TEST_SIZE);

    start = rdtsc();
    cache_probe(test_buffer.data(), TEST_SIZE);
    end = rdtsc();

    double uncached_latency = static_cast<double>(end - start);

    // Calculate ratio
    double ratio = uncached_latency / (cached_latency + 1.0);

    // Under normal conditions, ratio should be > 3.0
    // Under surveillance, timing differences become smaller
    if (ratio < 2.0) {
        return 0.8f; // High confidence anomaly
    } else if (ratio < 3.0) {
        return 0.4f; // Medium confidence anomaly
    }

    return 0.0f; // No anomaly
}

float EL2Detector::detect_perf_counter_blocking() {
    // On iOS, we can't directly detect perf counter blocking
    // Instead, check if our counters are returning reasonable values

    PerfCounterData perf;
    if (!perf_counters_.read_counters(perf)) {
        return 0.9f; // High confidence - can't read counters at all
    }

    // Check if counters seem realistic
    if (perf.cycles == 0 || perf.instructions == 0) {
        return 0.7f; // Medium-high confidence
    }

    // Check CPI (cycles per instruction) - should be 0.5 to 4.0 typically
    double cpi = static_cast<double>(perf.cycles) / perf.instructions;
    if (cpi < 0.1 || cpi > 10.0) {
        return 0.5f; // Suspicious values
    }

    return 0.0f; // Counters seem accessible
}

float EL2Detector::detect_memory_anomalies() {
    PerfCounterData perf;
    if (!perf_counters_.read_counters(perf)) {
        return 0.0f;
    }

    // Check cache miss rate
    if (perf.cache_references > 0) {
        double miss_rate = static_cast<double>(perf.cache_misses) / perf.cache_references;

        // Compare to baseline
        if (baseline_.avg_cache_miss_rate > 0) {
            double deviation = std::abs(miss_rate - baseline_.avg_cache_miss_rate) / baseline_.avg_cache_miss_rate;

            if (deviation > 1.0) { // 100% deviation
                return 0.7f;
            } else if (deviation > 0.5) { // 50% deviation
                return 0.4f;
            }
        }
    }

    return 0.0f;
}

float EL2Detector::detect_jailbreak_indicators() {
    float score = 0.0f;

    // Check for common jailbreak files (basic detection)
    const char* jailbreak_paths[] = {
        "/Applications/Cydia.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt/",
        nullptr
    };

    for (int i = 0; jailbreak_paths[i] != nullptr; i++) {
        FILE* f = fopen(jailbreak_paths[i], "r");
        if (f) {
            fclose(f);
            score += 0.3f;
        }
    }

    // Check if we can write to restricted areas
    FILE* f = fopen("/private/jailbreak.txt", "w");
    if (f) {
        fclose(f);
        unlink("/private/jailbreak.txt");
        score += 0.3f;
    }

    // Check for suspicious dylibs
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && (strstr(name, "Substrate") || strstr(name, "Cydia"))) {
            score += 0.2f;
        }
    }

    return (score > 1.0f) ? 1.0f : score;
}

float EL2Detector::detect_debugger_attachment() {
    // Check if debugger is attached using sysctl
    int mib[4];
    struct kinfo_proc info;
    size_t size = sizeof(info);

    info.kp_proc.p_flag = 0;

    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_PID;
    mib[3] = getpid();

    if (sysctl(mib, 4, &info, &size, nullptr, 0) == 0) {
        if (info.kp_proc.p_flag & P_TRACED) {
            return 1.0f; // Debugger definitely attached
        }
    }

    return 0.0f;
}

float EL2Detector::detect_code_signing_tampering() {
    // Basic check - in production you'd use more sophisticated methods
    // Check if code signature is valid using SecStaticCodeCheckValidityWithErrors

    // For now, return low score (assume not tampered)
    return 0.0f;
}

uint64_t EL2Detector::rdtsc() {
    return emma::platform::read_timestamp_counter();
}

void EL2Detector::cache_flush(void* ptr, size_t size) {
    CacheOperations::flush_cache_range(ptr, size);
}

void EL2Detector::cache_probe(void* ptr, size_t size) {
    volatile uint8_t* buf = static_cast<volatile uint8_t*>(ptr);
    volatile uint8_t dummy = 0;

    for (size_t i = 0; i < size; i += 64) { // 64-byte cache lines
        dummy += buf[i];
    }

    emma::platform::memory_barrier();
}

} // namespace security
} // namespace emma
