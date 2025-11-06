#include "timing_obfuscation.h"
#include "../../Common/ios_platform.h"
#include <random>
#include <thread>
#include <chrono>
#include <cmath>

namespace emma {
namespace security {

void TimingObfuscation::random_delay_us(int min_us, int max_us) {
    if (min_us < 0) min_us = 0;
    if (max_us < min_us) max_us = min_us;

    static std::random_device rd;
    static std::mt19937 gen(rd());
    std::uniform_int_distribution<> dis(min_us, max_us);

    int delay = dis(gen);
    busy_wait_us(delay);
}

void TimingObfuscation::exponential_delay_us(int mean_us) {
    if (mean_us <= 0) return;

    static std::random_device rd;
    static std::mt19937 gen(rd());
    std::exponential_distribution<double> dis(1.0 / mean_us);

    int delay = static_cast<int>(dis(gen));
    busy_wait_us(delay);
}

void TimingObfuscation::execute_with_obfuscation(std::function<void()> func, int chaos_percent) {
    if (chaos_percent < 0) chaos_percent = 0;
    if (chaos_percent > 100) chaos_percent = 100;

    // Add pre-execution delay
    int pre_delay = (chaos_percent * 1000) / 100; // 0-10ms based on chaos
    random_delay_us(0, pre_delay);

    // Add timing noise during execution
    add_timing_noise(chaos_percent / 2);

    // Execute the actual function
    func();

    // Add post-execution delay
    int post_delay = (chaos_percent * 2000) / 100; // 0-20ms based on chaos
    random_delay_us(0, post_delay);

    // Add more timing noise
    add_timing_noise(chaos_percent / 2);
}

void TimingObfuscation::add_timing_noise(int intensity_percent) {
    if (intensity_percent < 0) intensity_percent = 0;
    if (intensity_percent > 100) intensity_percent = 100;

    // Calculate number of dummy operations based on intensity
    int operations = (intensity_percent * 1000) / 100;

    volatile uint64_t dummy = 0;
    static std::random_device rd;
    static std::mt19937 gen(rd());
    std::uniform_int_distribution<uint64_t> dis;

    for (int i = 0; i < operations; i++) {
        // Mix of operations to create timing noise
        uint64_t val = dis(gen);

        switch (i % 5) {
            case 0:
                dummy += val;
                break;
            case 1:
                dummy *= val;
                break;
            case 2:
                dummy ^= val;
                break;
            case 3:
                dummy = (dummy << 3) | (dummy >> 61);
                break;
            case 4:
                dummy = dummy * 6364136223846793005ULL + 1442695040888963407ULL;
                break;
        }
    }

    // Ensure the operations aren't optimized away
    emma::platform::memory_barrier();
}

void TimingObfuscation::jitter_sleep_ms(int base_ms, int jitter_percent) {
    if (base_ms < 0) base_ms = 0;
    if (jitter_percent < 0) jitter_percent = 0;
    if (jitter_percent > 100) jitter_percent = 100;

    // Calculate jitter amount
    int jitter_ms = (base_ms * jitter_percent) / 100;

    static std::random_device rd;
    static std::mt19937 gen(rd());
    std::uniform_int_distribution<> dis(-jitter_ms, jitter_ms);

    int actual_sleep_ms = base_ms + dis(gen);
    if (actual_sleep_ms < 0) actual_sleep_ms = 0;

    // Use a mix of sleep and busy-wait for less predictable timing
    if (actual_sleep_ms > 10) {
        int sleep_portion = actual_sleep_ms * 70 / 100; // 70% sleep
        int busy_portion = actual_sleep_ms - sleep_portion; // 30% busy-wait

        std::this_thread::sleep_for(std::chrono::milliseconds(sleep_portion));
        busy_wait_us(busy_portion * 1000);
    } else {
        busy_wait_us(actual_sleep_ms * 1000);
    }
}

void TimingObfuscation::busy_wait_us(int duration_us) {
    if (duration_us <= 0) return;

    // Get timer frequency
    static uint64_t freq = emma::platform::get_timestamp_frequency();

    // Calculate target cycles
    uint64_t cycles_to_wait = (static_cast<uint64_t>(duration_us) * freq) / 1000000;

    uint64_t start = emma::platform::read_timestamp_counter();
    uint64_t end = start + cycles_to_wait;

    // Busy wait with some computational work to prevent optimization
    volatile uint64_t dummy = 0;
    while (emma::platform::read_timestamp_counter() < end) {
        dummy++;
    }
}

} // namespace security
} // namespace emma
