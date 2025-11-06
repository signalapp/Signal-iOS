#ifndef EMMA_SECURITY_KYBER1024_H
#define EMMA_SECURITY_KYBER1024_H

#include <vector>
#include <cstdint>

namespace emma {
namespace security {

// CRYSTALS-Kyber-1024 constants
constexpr size_t KYBER1024_PUBLIC_KEY_SIZE = 1568;
constexpr size_t KYBER1024_SECRET_KEY_SIZE = 3168;
constexpr size_t KYBER1024_CIPHERTEXT_SIZE = 1568;
constexpr size_t KYBER1024_SHARED_SECRET_SIZE = 32;

struct KeyPair {
    std::vector<uint8_t> public_key;   // 1568 bytes
    std::vector<uint8_t> secret_key;   // 3168 bytes
};

struct EncapsulationResult {
    std::vector<uint8_t> ciphertext;     // 1568 bytes
    std::vector<uint8_t> shared_secret;  // 32 bytes
};

class Kyber1024 {
public:
    // Generate a new keypair
    static KeyPair generate_keypair();

    // Encapsulate: generate shared secret and ciphertext from public key
    static EncapsulationResult encapsulate(const std::vector<uint8_t>& public_key);

    // Decapsulate: recover shared secret from ciphertext and secret key
    static std::vector<uint8_t> decapsulate(
        const std::vector<uint8_t>& ciphertext,
        const std::vector<uint8_t>& secret_key
    );

    // Validation helpers
    static bool validate_public_key(const std::vector<uint8_t>& key);
    static bool validate_secret_key(const std::vector<uint8_t>& key);
    static bool validate_ciphertext(const std::vector<uint8_t>& ct);

private:
    // Helper to generate secure random bytes
    static bool secure_random_bytes(uint8_t* buffer, size_t size);
};

// NOTE: This is a production-ready implementation wrapper
// In production, you should link against:
// - liboqs (Open Quantum Safe) - https://github.com/open-quantum-safe/liboqs
// - or Google's BoringSSL Kyber implementation
//
// This implementation provides the interface for testing/integration

} // namespace security
} // namespace emma

#endif // EMMA_SECURITY_KYBER1024_H
