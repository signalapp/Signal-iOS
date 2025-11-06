#ifndef EMMA_SECURITY_NIST_PQC_H
#define EMMA_SECURITY_NIST_PQC_H

// NIST Post-Quantum Cryptography (PQC) Standards
// https://csrc.nist.gov/Projects/post-quantum-cryptography

#include <vector>
#include <cstdint>

namespace emma {
namespace security {

// ============================================================================
// ML-KEM-1024 (Module-Lattice-Based Key Encapsulation Mechanism)
// Formerly known as CRYSTALS-Kyber
// FIPS 203: https://csrc.nist.gov/pubs/fips/203/final
// ============================================================================

// ML-KEM-1024 constants (NIST FIPS 203)
constexpr size_t ML_KEM_1024_PUBLIC_KEY_SIZE = 1568;
constexpr size_t ML_KEM_1024_SECRET_KEY_SIZE = 3168;
constexpr size_t ML_KEM_1024_CIPHERTEXT_SIZE = 1568;
constexpr size_t ML_KEM_1024_SHARED_SECRET_SIZE = 32;

// Backward compatibility aliases (deprecated, use ML-KEM names)
constexpr size_t KYBER1024_PUBLIC_KEY_SIZE = ML_KEM_1024_PUBLIC_KEY_SIZE;
constexpr size_t KYBER1024_SECRET_KEY_SIZE = ML_KEM_1024_SECRET_KEY_SIZE;
constexpr size_t KYBER1024_CIPHERTEXT_SIZE = ML_KEM_1024_CIPHERTEXT_SIZE;
constexpr size_t KYBER1024_SHARED_SECRET_SIZE = ML_KEM_1024_SHARED_SECRET_SIZE;

struct MLKEMKeyPair {
    std::vector<uint8_t> public_key;   // 1568 bytes
    std::vector<uint8_t> secret_key;   // 3168 bytes
};

struct MLKEMEncapsulationResult {
    std::vector<uint8_t> ciphertext;     // 1568 bytes
    std::vector<uint8_t> shared_secret;  // 32 bytes
};

// Backward compatibility alias
using KeyPair = MLKEMKeyPair;
using EncapsulationResult = MLKEMEncapsulationResult;

// ============================================================================
// ML-DSA-87 (Module-Lattice-Based Digital Signature Algorithm)
// Formerly known as CRYSTALS-Dilithium
// FIPS 204: https://csrc.nist.gov/pubs/fips/204/final
// ============================================================================

// ML-DSA-87 constants (NIST FIPS 204)
constexpr size_t ML_DSA_87_PUBLIC_KEY_SIZE = 2592;
constexpr size_t ML_DSA_87_SECRET_KEY_SIZE = 4896;
constexpr size_t ML_DSA_87_SIGNATURE_SIZE = 4627;

struct MLDSAKeyPair {
    std::vector<uint8_t> public_key;   // 2592 bytes
    std::vector<uint8_t> secret_key;   // 4896 bytes
};

struct MLDSASignature {
    std::vector<uint8_t> signature;    // 4627 bytes
};

// ============================================================================
// ML-KEM-1024 Class (NIST FIPS 203 compliant)
// ============================================================================

class MLKEM1024 {
public:
    // Key Generation
    static MLKEMKeyPair generate_keypair();

    // Encapsulation: generate shared secret and ciphertext from public key
    static MLKEMEncapsulationResult encapsulate(const std::vector<uint8_t>& public_key);

    // Decapsulation: recover shared secret from ciphertext and secret key
    static std::vector<uint8_t> decapsulate(
        const std::vector<uint8_t>& ciphertext,
        const std::vector<uint8_t>& secret_key
    );

    // Validation helpers
    static bool validate_public_key(const std::vector<uint8_t>& key);
    static bool validate_secret_key(const std::vector<uint8_t>& key);
    static bool validate_ciphertext(const std::vector<uint8_t>& ct);

private:
    static bool secure_random_bytes(uint8_t* buffer, size_t size);
};

// ============================================================================
// ML-DSA-87 Class (NIST FIPS 204 compliant)
// ============================================================================

class MLDSA87 {
public:
    // Key Generation
    static MLDSAKeyPair generate_keypair();

    // Sign: create signature for message
    static MLDSASignature sign(
        const std::vector<uint8_t>& message,
        const std::vector<uint8_t>& secret_key
    );

    // Verify: verify signature for message
    static bool verify(
        const std::vector<uint8_t>& message,
        const std::vector<uint8_t>& signature,
        const std::vector<uint8_t>& public_key
    );

    // Validation helpers
    static bool validate_public_key(const std::vector<uint8_t>& key);
    static bool validate_secret_key(const std::vector<uint8_t>& key);
    static bool validate_signature(const std::vector<uint8_t>& sig);

private:
    static bool secure_random_bytes(uint8_t* buffer, size_t size);
};

// ============================================================================
// Backward Compatibility Alias (deprecated, use MLKEM1024)
// ============================================================================

class Kyber1024 {
public:
    [[deprecated("Use MLKEM1024 instead - Kyber is now standardized as ML-KEM")]]
    static KeyPair generate_keypair() {
        return MLKEM1024::generate_keypair();
    }

    [[deprecated("Use MLKEM1024 instead - Kyber is now standardized as ML-KEM")]]
    static EncapsulationResult encapsulate(const std::vector<uint8_t>& public_key) {
        return MLKEM1024::encapsulate(public_key);
    }

    [[deprecated("Use MLKEM1024 instead - Kyber is now standardized as ML-KEM")]]
    static std::vector<uint8_t> decapsulate(
        const std::vector<uint8_t>& ciphertext,
        const std::vector<uint8_t>& secret_key
    ) {
        return MLKEM1024::decapsulate(ciphertext, secret_key);
    }

    [[deprecated("Use MLKEM1024 instead")]]
    static bool validate_public_key(const std::vector<uint8_t>& key) {
        return MLKEM1024::validate_public_key(key);
    }

    [[deprecated("Use MLKEM1024 instead")]]
    static bool validate_secret_key(const std::vector<uint8_t>& key) {
        return MLKEM1024::validate_secret_key(key);
    }

    [[deprecated("Use MLKEM1024 instead")]]
    static bool validate_ciphertext(const std::vector<uint8_t>& ct) {
        return MLKEM1024::validate_ciphertext(ct);
    }
};

// ============================================================================
// Combined Protocol: ML-KEM + ML-DSA + AES-256-GCM
// ============================================================================

struct SecureChannelKeys {
    std::vector<uint8_t> encryption_key;  // 32 bytes for AES-256-GCM
    std::vector<uint8_t> mac_key;         // 32 bytes for HMAC-SHA256
    std::vector<uint8_t> session_id;      // 32 bytes unique session identifier
};

class NISTCompliantProtocol {
public:
    // Establish secure channel with key exchange + signatures
    static SecureChannelKeys establish_channel(
        const MLKEMKeyPair& local_kem_keypair,
        const MLDSAKeyPair& local_dsa_keypair,
        const std::vector<uint8_t>& remote_kem_public_key,
        const std::vector<uint8_t>& remote_dsa_public_key
    );

    // Verify and derive keys from received ciphertext
    static SecureChannelKeys accept_channel(
        const std::vector<uint8_t>& kem_ciphertext,
        const MLDSASignature& signature,
        const MLKEMKeyPair& local_kem_keypair,
        const std::vector<uint8_t>& remote_dsa_public_key
    );

    // Derive AES-256-GCM and HMAC keys from shared secret
    static SecureChannelKeys derive_channel_keys(
        const std::vector<uint8_t>& shared_secret,
        const std::vector<uint8_t>& context_info
    );
};

// NOTE: This is a production-ready interface wrapper
// In production, you should link against:
// - liboqs (Open Quantum Safe) - https://github.com/open-quantum-safe/liboqs
// - or NIST reference implementations
//
// This implementation provides the interface for testing/integration

} // namespace security
} // namespace emma

#endif // EMMA_SECURITY_NIST_PQC_H
