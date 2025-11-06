#ifndef EMMA_SECURITY_TIMING_OBFUSCATION_H
#define EMMA_SECURITY_TIMING_OBFUSCATION_H

#include <cstdint>
#include <functional>

namespace emma {
namespace security {

class TimingObfuscation {
public:
    // Random delay in microseconds
    static void random_delay_us(int min_us, int max_us);

    // Exponential delay (for protocol obfuscation)
    static void exponential_delay_us(int mean_us);

    // Execute function with timing obfuscation
    static void execute_with_obfuscation(std::function<void()> func, int chaos_percent);

    // Add computational noise to timing
    static void add_timing_noise(int intensity_percent);

    // Sleep with jitter
    static void jitter_sleep_ms(int base_ms, int jitter_percent);

private:
    // Busy wait for microseconds (high precision)
    static void busy_wait_us(int duration_us);
};

} // namespace security
} // namespace emma

#endif // EMMA_SECURITY_TIMING_OBFUSCATION_H
