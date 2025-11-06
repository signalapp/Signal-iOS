#ifndef EMMA_SECURITY_EL2_DETECTOR_H
#define EMMA_SECURITY_EL2_DETECTOR_H

#include "performance_counters.h"
#include <cstdint>
#include <cstddef>

namespace emma {
namespace security {

struct ThreatAnalysis {
    float threat_level;                  // 0.0 - 1.0
    float hypervisor_confidence;         // 0.0 - 1.0
    bool timing_anomaly_detected;
    bool cache_anomaly_detected;
    bool perf_counter_blocked;
    bool memory_anomaly_detected;
    uint64_t analysis_timestamp;
};

class EL2Detector {
public:
    EL2Detector();
    ~EL2Detector();

    bool initialize();
    ThreatAnalysis analyze_threat();

private:
    // Detection methods
    float detect_timing_anomalies();
    float detect_cache_anomalies();
    float detect_perf_counter_blocking();
    float detect_memory_anomalies();

    // iOS-specific detection methods
    float detect_jailbreak_indicators();
    float detect_debugger_attachment();
    float detect_code_signing_tampering();

    // Helper methods
    void establish_baseline();
    uint64_t rdtsc();
    void cache_flush(void* ptr, size_t size);
    void cache_probe(void* ptr, size_t size);

    // Baseline data
    struct Baseline {
        double avg_cache_latency;
        double avg_instruction_latency;
        double avg_cycles_per_instruction;
        double avg_cache_miss_rate;
        uint64_t baseline_timestamp;
    } baseline_;

    PerformanceCounters perf_counters_;
    bool initialized_;
    uint64_t last_analysis_time_;
    int consecutive_detections_;
};

} // namespace security
} // namespace emma

#endif // EMMA_SECURITY_EL2_DETECTOR_H
