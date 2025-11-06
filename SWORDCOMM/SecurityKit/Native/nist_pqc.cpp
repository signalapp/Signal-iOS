#include "nist_pqc.h"
#include "liboqs_wrapper.h"
#include "../../Common/ios_platform.h"
#include <stdexcept>
#include <cstring>
#include <algorithm>

// Initialize liboqs once (thread-safe in C++11)
static bool init_liboqs_once() {
    static bool initialized = liboqs_init();
    return initialized;
}

namespace emma {
namespace security {

// ============================================================================
// ML-KEM-1024 Implementation (NIST FIPS 203)
// ============================================================================

MLKEMKeyPair MLKEM1024::generate_keypair() {
    // Ensure liboqs is initialized
    init_liboqs_once();

    MLKEMKeyPair kp;
    kp.public_key.resize(ML_KEM_1024_PUBLIC_KEY_SIZE);
    kp.secret_key.resize(ML_KEM_1024_SECRET_KEY_SIZE);

    // Use liboqs for production ML-KEM-1024 keypair generation
    int result = liboqs_ml_kem_1024_keypair(
        kp.public_key.data(),
        kp.secret_key.data()
    );

    if (result != 0) {
        throw std::runtime_error("Failed to generate ML-KEM-1024 keypair");
    }

    if (liboqs_ml_kem_1024_enabled()) {
        SWORDCOMM_LOG_INFO("Generated ML-KEM-1024 keypair (NIST FIPS 203) - PRODUCTION");
    } else {
        SWORDCOMM_LOG_WARN("Generated ML-KEM-1024 keypair - STUB MODE (NOT SECURE)");
    }

    return kp;
}

MLKEMEncapsulationResult MLKEM1024::encapsulate(const std::vector<uint8_t>& public_key) {
    if (!validate_public_key(public_key)) {
        throw std::invalid_argument("Invalid ML-KEM public key size");
    }

    MLKEMEncapsulationResult result;
    result.ciphertext.resize(ML_KEM_1024_CIPHERTEXT_SIZE);
    result.shared_secret.resize(ML_KEM_1024_SHARED_SECRET_SIZE);

    // Use liboqs for production ML-KEM-1024 encapsulation
    int ret = liboqs_ml_kem_1024_encapsulate(
        result.ciphertext.data(),
        result.shared_secret.data(),
        public_key.data()
    );

    if (ret != 0) {
        throw std::runtime_error("Failed to perform ML-KEM-1024 encapsulation");
    }

    SWORDCOMM_LOG_DEBUG("ML-KEM-1024 encapsulation successful");

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

    // Use liboqs for production ML-KEM-1024 decapsulation
    int ret = liboqs_ml_kem_1024_decapsulate(
        shared_secret.data(),
        ciphertext.data(),
        secret_key.data()
    );

    if (ret != 0) {
        throw std::runtime_error("Failed to perform ML-KEM-1024 decapsulation");
    }

    SWORDCOMM_LOG_DEBUG("ML-KEM-1024 decapsulation successful");

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
    // Ensure liboqs is initialized
    init_liboqs_once();

    MLDSAKeyPair kp;
    kp.public_key.resize(ML_DSA_87_PUBLIC_KEY_SIZE);
    kp.secret_key.resize(ML_DSA_87_SECRET_KEY_SIZE);

    // Use liboqs for production ML-DSA-87 keypair generation
    int result = liboqs_ml_dsa_87_keypair(
        kp.public_key.data(),
        kp.secret_key.data()
    );

    if (result != 0) {
        throw std::runtime_error("Failed to generate ML-DSA-87 keypair");
    }

    if (liboqs_ml_dsa_87_enabled()) {
        SWORDCOMM_LOG_INFO("Generated ML-DSA-87 keypair (NIST FIPS 204) - PRODUCTION");
    } else {
        SWORDCOMM_LOG_WARN("Generated ML-DSA-87 keypair - STUB MODE (NOT SECURE)");
    }

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

    // Use liboqs for production ML-DSA-87 signing
    size_t signature_len = ML_DSA_87_SIGNATURE_SIZE;
    int ret = liboqs_ml_dsa_87_sign(
        sig.signature.data(),
        &signature_len,
        message.data(),
        message.size(),
        secret_key.data()
    );

    if (ret != 0) {
        throw std::runtime_error("Failed to perform ML-DSA-87 signing");
    }

    // Resize to actual signature length (may be less than maximum)
    sig.signature.resize(signature_len);

    SWORDCOMM_LOG_DEBUG("ML-DSA-87 sign: %zu bytes message -> %zu bytes signature",
                   message.size(), signature_len);

    return sig;
}

bool MLDSA87::verify(
    const std::vector<uint8_t>& message,
    const std::vector<uint8_t>& signature,
    const std::vector<uint8_t>& public_key) {

    if (!validate_public_key(public_key)) {
        SWORDCOMM_LOG_ERROR("Invalid ML-DSA public key size");
        return false;
    }

    if (signature.empty()) {
        SWORDCOMM_LOG_ERROR("Empty ML-DSA signature");
        return false;
    }

    if (message.empty()) {
        SWORDCOMM_LOG_ERROR("Cannot verify empty message");
        return false;
    }

    // Use liboqs for production ML-DSA-87 verification
    int ret = liboqs_ml_dsa_87_verify(
        message.data(),
        message.size(),
        signature.data(),
        signature.size(),
        public_key.data()
    );

    bool valid = (ret == 0);

    if (valid) {
        SWORDCOMM_LOG_DEBUG("ML-DSA-87 signature verified successfully");
    } else {
        SWORDCOMM_LOG_WARN("ML-DSA-87 signature verification failed");
    }

    return valid;
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

    SWORDCOMM_LOG_INFO("Established secure channel (ML-KEM + ML-DSA + AES-256-GCM)");

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

    SWORDCOMM_LOG_INFO("Accepted secure channel (ML-KEM + ML-DSA + AES-256-GCM)");

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

    SWORDCOMM_LOG_DEBUG("Derived channel keys: enc=32B, mac=32B, session=32B");

    return keys;
}

} // namespace security
} // namespace emma
