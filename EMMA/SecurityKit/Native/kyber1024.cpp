#include "kyber1024.h"
#include "../../Common/ios_platform.h"
#include <stdexcept>

namespace emma {
namespace security {

KeyPair Kyber1024::generate_keypair() {
    KeyPair kp;
    kp.public_key.resize(KYBER1024_PUBLIC_KEY_SIZE);
    kp.secret_key.resize(KYBER1024_SECRET_KEY_SIZE);

    // TODO: Replace with actual liboqs implementation
    // For now, generate random bytes for testing
    if (!secure_random_bytes(kp.public_key.data(), KYBER1024_PUBLIC_KEY_SIZE)) {
        throw std::runtime_error("Failed to generate public key");
    }

    if (!secure_random_bytes(kp.secret_key.data(), KYBER1024_SECRET_KEY_SIZE)) {
        throw std::runtime_error("Failed to generate secret key");
    }

    EMMA_LOG_INFO("Generated Kyber-1024 keypair (TEST MODE - replace with liboqs)");

    return kp;
}

EncapsulationResult Kyber1024::encapsulate(const std::vector<uint8_t>& public_key) {
    if (!validate_public_key(public_key)) {
        throw std::invalid_argument("Invalid public key size");
    }

    EncapsulationResult result;
    result.ciphertext.resize(KYBER1024_CIPHERTEXT_SIZE);
    result.shared_secret.resize(KYBER1024_SHARED_SECRET_SIZE);

    // TODO: Replace with actual liboqs implementation
    // For now, generate random bytes for testing
    if (!secure_random_bytes(result.ciphertext.data(), KYBER1024_CIPHERTEXT_SIZE)) {
        throw std::runtime_error("Failed to generate ciphertext");
    }

    if (!secure_random_bytes(result.shared_secret.data(), KYBER1024_SHARED_SECRET_SIZE)) {
        throw std::runtime_error("Failed to generate shared secret");
    }

    EMMA_LOG_DEBUG("Encapsulated shared secret (TEST MODE)");

    return result;
}

std::vector<uint8_t> Kyber1024::decapsulate(
    const std::vector<uint8_t>& ciphertext,
    const std::vector<uint8_t>& secret_key) {

    if (!validate_ciphertext(ciphertext)) {
        throw std::invalid_argument("Invalid ciphertext size");
    }

    if (!validate_secret_key(secret_key)) {
        throw std::invalid_argument("Invalid secret key size");
    }

    std::vector<uint8_t> shared_secret(KYBER1024_SHARED_SECRET_SIZE);

    // TODO: Replace with actual liboqs implementation
    // For now, generate random bytes for testing
    if (!secure_random_bytes(shared_secret.data(), KYBER1024_SHARED_SECRET_SIZE)) {
        throw std::runtime_error("Failed to recover shared secret");
    }

    EMMA_LOG_DEBUG("Decapsulated shared secret (TEST MODE)");

    return shared_secret;
}

bool Kyber1024::validate_public_key(const std::vector<uint8_t>& key) {
    return key.size() == KYBER1024_PUBLIC_KEY_SIZE;
}

bool Kyber1024::validate_secret_key(const std::vector<uint8_t>& key) {
    return key.size() == KYBER1024_SECRET_KEY_SIZE;
}

bool Kyber1024::validate_ciphertext(const std::vector<uint8_t>& ct) {
    return ct.size() == KYBER1024_CIPHERTEXT_SIZE;
}

bool Kyber1024::secure_random_bytes(uint8_t* buffer, size_t size) {
    return emma::platform::secure_random_bytes(buffer, size);
}

} // namespace security
} // namespace emma
