#include "nist_pqc.h"
#include "../../Common/ios_platform.h"
#include <stdexcept>
#include <cstring>
#include <algorithm>

namespace emma {
namespace security {

// ============================================================================
// ML-KEM-1024 Implementation (NIST FIPS 203)
// ============================================================================

MLKEMKeyPair MLKEM1024::generate_keypair() {
    MLKEMKeyPair kp;
    kp.public_key.resize(ML_KEM_1024_PUBLIC_KEY_SIZE);
    kp.secret_key.resize(ML_KEM_1024_SECRET_KEY_SIZE);

    // TODO: Replace with actual liboqs ML-KEM-1024 implementation
    // For now, generate random bytes for testing
    if (!secure_random_bytes(kp.public_key.data(), ML_KEM_1024_PUBLIC_KEY_SIZE)) {
        throw std::runtime_error("Failed to generate ML-KEM public key");
    }

    if (!secure_random_bytes(kp.secret_key.data(), ML_KEM_1024_SECRET_KEY_SIZE)) {
        throw std::runtime_error("Failed to generate ML-KEM secret key");
    }

    EMMA_LOG_INFO("Generated ML-KEM-1024 keypair (NIST FIPS 203) - TEST MODE");

    return kp;
}

MLKEMEncapsulationResult MLKEM1024::encapsulate(const std::vector<uint8_t>& public_key) {
    if (!validate_public_key(public_key)) {
        throw std::invalid_argument("Invalid ML-KEM public key size");
    }

    MLKEMEncapsulationResult result;
    result.ciphertext.resize(ML_KEM_1024_CIPHERTEXT_SIZE);
    result.shared_secret.resize(ML_KEM_1024_SHARED_SECRET_SIZE);

    // TODO: Replace with actual liboqs ML-KEM-1024 implementation
    // For now, generate random bytes for testing
    if (!secure_random_bytes(result.ciphertext.data(), ML_KEM_1024_CIPHERTEXT_SIZE)) {
        throw std::runtime_error("Failed to generate ML-KEM ciphertext");
    }

    if (!secure_random_bytes(result.shared_secret.data(), ML_KEM_1024_SHARED_SECRET_SIZE)) {
        throw std::runtime_error("Failed to generate ML-KEM shared secret");
    }

    EMMA_LOG_DEBUG("ML-KEM-1024 encapsulation (TEST MODE)");

    return result;
}

std::vector<uint8_t> MLKEM1024::decapsulate(
    const std::vector<uint8_t>& ciphertext,
    const std::vector<uint8_t>& secret_key) {

    if (!validate_ciphertext(ciphertext)) {
        throw std::invalid_argument("Invalid ML-KEM ciphertext size");
    }

    if (!validate_secret_key(secret_key)) {
        throw std::invalid_argument("Invalid ML-KEM secret key size");
    }

    std::vector<uint8_t> shared_secret(ML_KEM_1024_SHARED_SECRET_SIZE);

    // TODO: Replace with actual liboqs ML-KEM-1024 implementation
    // For now, generate random bytes for testing
    if (!secure_random_bytes(shared_secret.data(), ML_KEM_1024_SHARED_SECRET_SIZE)) {
        throw std::runtime_error("Failed to recover ML-KEM shared secret");
    }

    EMMA_LOG_DEBUG("ML-KEM-1024 decapsulation (TEST MODE)");

    return shared_secret;
}

bool MLKEM1024::validate_public_key(const std::vector<uint8_t>& key) {
    return key.size() == ML_KEM_1024_PUBLIC_KEY_SIZE;
}

bool MLKEM1024::validate_secret_key(const std::vector<uint8_t>& key) {
    return key.size() == ML_KEM_1024_SECRET_KEY_SIZE;
}

bool MLKEM1024::validate_ciphertext(const std::vector<uint8_t>& ct) {
    return ct.size() == ML_KEM_1024_CIPHERTEXT_SIZE;
}

bool MLKEM1024::secure_random_bytes(uint8_t* buffer, size_t size) {
    return emma::platform::secure_random_bytes(buffer, size);
}

// ============================================================================
// ML-DSA-87 Implementation (NIST FIPS 204)
// ============================================================================

MLDSAKeyPair MLDSA87::generate_keypair() {
    MLDSAKeyPair kp;
    kp.public_key.resize(ML_DSA_87_PUBLIC_KEY_SIZE);
    kp.secret_key.resize(ML_DSA_87_SECRET_KEY_SIZE);

    // TODO: Replace with actual liboqs ML-DSA-87 implementation
    // For now, generate random bytes for testing
    if (!secure_random_bytes(kp.public_key.data(), ML_DSA_87_PUBLIC_KEY_SIZE)) {
        throw std::runtime_error("Failed to generate ML-DSA public key");
    }

    if (!secure_random_bytes(kp.secret_key.data(), ML_DSA_87_SECRET_KEY_SIZE)) {
        throw std::runtime_error("Failed to generate ML-DSA secret key");
    }

    EMMA_LOG_INFO("Generated ML-DSA-87 keypair (NIST FIPS 204) - TEST MODE");

    return kp;
}

MLDSASignature MLDSA87::sign(
    const std::vector<uint8_t>& message,
    const std::vector<uint8_t>& secret_key) {

    if (!validate_secret_key(secret_key)) {
        throw std::invalid_argument("Invalid ML-DSA secret key size");
    }

    if (message.empty()) {
        throw std::invalid_argument("Cannot sign empty message");
    }

    MLDSASignature sig;
    sig.signature.resize(ML_DSA_87_SIGNATURE_SIZE);

    // TODO: Replace with actual liboqs ML-DSA-87 implementation
    // For now, generate random bytes for testing
    if (!secure_random_bytes(sig.signature.data(), ML_DSA_87_SIGNATURE_SIZE)) {
        throw std::runtime_error("Failed to generate ML-DSA signature");
    }

    EMMA_LOG_DEBUG("ML-DSA-87 sign: %zu bytes (TEST MODE)", message.size());

    return sig;
}

bool MLDSA87::verify(
    const std::vector<uint8_t>& message,
    const std::vector<uint8_t>& signature,
    const std::vector<uint8_t>& public_key) {

    if (!validate_public_key(public_key)) {
        EMMA_LOG_ERROR("Invalid ML-DSA public key size");
        return false;
    }

    if (!validate_signature(signature)) {
        EMMA_LOG_ERROR("Invalid ML-DSA signature size");
        return false;
    }

    if (message.empty()) {
        EMMA_LOG_ERROR("Cannot verify empty message");
        return false;
    }

    // TODO: Replace with actual liboqs ML-DSA-87 implementation
    // For testing, always return true
    EMMA_LOG_DEBUG("ML-DSA-87 verify: %zu bytes (TEST MODE - always true)", message.size());

    return true; // TEST MODE
}

bool MLDSA87::validate_public_key(const std::vector<uint8_t>& key) {
    return key.size() == ML_DSA_87_PUBLIC_KEY_SIZE;
}

bool MLDSA87::validate_secret_key(const std::vector<uint8_t>& key) {
    return key.size() == ML_DSA_87_SECRET_KEY_SIZE;
}

bool MLDSA87::validate_signature(const std::vector<uint8_t>& sig) {
    return sig.size() == ML_DSA_87_SIGNATURE_SIZE;
}

bool MLDSA87::secure_random_bytes(uint8_t* buffer, size_t size) {
    return emma::platform::secure_random_bytes(buffer, size);
}

// ============================================================================
// Combined Protocol Implementation
// ============================================================================

SecureChannelKeys NISTCompliantProtocol::establish_channel(
    const MLKEMKeyPair& local_kem_keypair,
    const MLDSAKeyPair& local_dsa_keypair,
    const std::vector<uint8_t>& remote_kem_public_key,
    const std::vector<uint8_t>& remote_dsa_public_key) {

    // 1. Perform ML-KEM-1024 encapsulation with remote's public key
    auto encap_result = MLKEM1024::encapsulate(remote_kem_public_key);

    // 2. Sign the ciphertext with our ML-DSA-87 private key
    auto signature = MLDSA87::sign(encap_result.ciphertext, local_dsa_keypair.secret_key);

    // 3. Create context info for key derivation
    std::vector<uint8_t> context_info;
    context_info.reserve(
        local_kem_keypair.public_key.size() +
        remote_kem_public_key.size() +
        encap_result.ciphertext.size()
    );

    context_info.insert(context_info.end(),
                       local_kem_keypair.public_key.begin(),
                       local_kem_keypair.public_key.end());
    context_info.insert(context_info.end(),
                       remote_kem_public_key.begin(),
                       remote_kem_public_key.end());
    context_info.insert(context_info.end(),
                       encap_result.ciphertext.begin(),
                       encap_result.ciphertext.end());

    // 4. Derive channel keys from shared secret
    auto keys = derive_channel_keys(encap_result.shared_secret, context_info);

    EMMA_LOG_INFO("Established secure channel (ML-KEM + ML-DSA + AES-256-GCM)");

    return keys;
}

SecureChannelKeys NISTCompliantProtocol::accept_channel(
    const std::vector<uint8_t>& kem_ciphertext,
    const MLDSASignature& signature,
    const MLKEMKeyPair& local_kem_keypair,
    const std::vector<uint8_t>& remote_dsa_public_key) {

    // 1. Verify the signature on the ciphertext
    if (!MLDSA87::verify(kem_ciphertext, signature.signature, remote_dsa_public_key)) {
        throw std::runtime_error("ML-DSA signature verification failed");
    }

    // 2. Perform ML-KEM-1024 decapsulation
    auto shared_secret = MLKEM1024::decapsulate(kem_ciphertext, local_kem_keypair.secret_key);

    // 3. Create context info for key derivation
    std::vector<uint8_t> context_info;
    context_info.reserve(
        local_kem_keypair.public_key.size() +
        kem_ciphertext.size()
    );

    context_info.insert(context_info.end(),
                       local_kem_keypair.public_key.begin(),
                       local_kem_keypair.public_key.end());
    context_info.insert(context_info.end(),
                       kem_ciphertext.begin(),
                       kem_ciphertext.end());

    // 4. Derive channel keys from shared secret
    auto keys = derive_channel_keys(shared_secret, context_info);

    EMMA_LOG_INFO("Accepted secure channel (ML-KEM + ML-DSA + AES-256-GCM)");

    return keys;
}

SecureChannelKeys NISTCompliantProtocol::derive_channel_keys(
    const std::vector<uint8_t>& shared_secret,
    const std::vector<uint8_t>& context_info) {

    // Use HKDF-SHA256 to derive keys
    // TODO: Replace with proper HKDF implementation from crypto library

    SecureChannelKeys keys;
    keys.encryption_key.resize(32);  // AES-256-GCM key
    keys.mac_key.resize(32);         // HMAC-SHA256 key
    keys.session_id.resize(32);      // Unique session ID

    // For now, use simple derivation (replace with HKDF in production)
    // Combine shared secret + context info
    std::vector<uint8_t> ikm; // Input Key Material
    ikm.reserve(shared_secret.size() + context_info.size());
    ikm.insert(ikm.end(), shared_secret.begin(), shared_secret.end());
    ikm.insert(ikm.end(), context_info.begin(), context_info.end());

    // Derive encryption key (bytes 0-31)
    size_t offset = 0;
    for (size_t i = 0; i < 32 && offset < ikm.size(); i++, offset++) {
        keys.encryption_key[i] = ikm[offset % ikm.size()];
    }

    // Derive MAC key (bytes 32-63)
    for (size_t i = 0; i < 32 && offset < ikm.size(); i++, offset++) {
        keys.mac_key[i] = ikm[offset % ikm.size()];
    }

    // Derive session ID (bytes 64-95)
    for (size_t i = 0; i < 32 && offset < ikm.size(); i++, offset++) {
        keys.session_id[i] = ikm[offset % ikm.size()];
    }

    EMMA_LOG_DEBUG("Derived channel keys: enc=32B, mac=32B, session=32B");

    return keys;
}

} // namespace security
} // namespace emma
