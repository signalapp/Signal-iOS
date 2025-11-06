//
//  hkdf.h
//  SWORDCOMM SecurityKit - HKDF-SHA256 Key Derivation
//
//  HMAC-based Extract-and-Expand Key Derivation Function (HKDF)
//  RFC 5869 implementation using SHA-256
//

#ifndef SWORDCOMM_HKDF_H
#define SWORDCOMM_HKDF_H

#include <stdint.h>
#include <stddef.h>
#include <vector>

namespace emma {
namespace security {

/// HKDF-SHA256 implementation (RFC 5869)
/// Used to derive encryption keys from ML-KEM shared secrets
class HKDF {
public:
    /// Perform HKDF-Extract
    /// Extracts a pseudorandom key from input keying material
    /// @param ikm Input keying material (e.g., ML-KEM shared secret)
    /// @param salt Optional salt value (use empty for no salt)
    /// @return Pseudorandom key (32 bytes for SHA-256)
    static std::vector<uint8_t> extract(
        const std::vector<uint8_t>& ikm,
        const std::vector<uint8_t>& salt = {}
    );

    /// Perform HKDF-Expand
    /// Expands a pseudorandom key to desired length
    /// @param prk Pseudorandom key from extract()
    /// @param info Optional context and application specific information
    /// @param length Desired output length in bytes (max 255 * 32 = 8160 bytes for SHA-256)
    /// @return Derived key material of specified length
    static std::vector<uint8_t> expand(
        const std::vector<uint8_t>& prk,
        const std::vector<uint8_t>& info,
        size_t length
    );

    /// Perform full HKDF (Extract + Expand)
    /// @param ikm Input keying material (e.g., ML-KEM shared secret)
    /// @param salt Optional salt value
    /// @param info Optional context and application specific information
    /// @param length Desired output length in bytes
    /// @return Derived key material of specified length
    static std::vector<uint8_t> derive_key(
        const std::vector<uint8_t>& ikm,
        const std::vector<uint8_t>& salt,
        const std::vector<uint8_t>& info,
        size_t length
    );

    /// Convenience function: Derive AES-256 key (32 bytes) from ML-KEM shared secret
    /// @param shared_secret ML-KEM-1024 shared secret (32 bytes)
    /// @param info Context information (e.g., "SWORDCOMM-AES-256-GCM-KEY")
    /// @return AES-256 key (32 bytes)
    static std::vector<uint8_t> derive_aes_key(
        const std::vector<uint8_t>& shared_secret,
        const std::vector<uint8_t>& info
    );

    /// Convenience function: Derive multiple keys from single shared secret
    /// @param shared_secret ML-KEM-1024 shared secret
    /// @param info Context information
    /// @param key_count Number of keys to derive
    /// @param key_length Length of each key in bytes
    /// @return Vector of derived keys
    static std::vector<std::vector<uint8_t>> derive_keys(
        const std::vector<uint8_t>& shared_secret,
        const std::vector<uint8_t>& info,
        size_t key_count,
        size_t key_length
    );

private:
    /// HMAC-SHA256 implementation
    /// @param key HMAC key
    /// @param data Data to authenticate
    /// @return HMAC output (32 bytes)
    static std::vector<uint8_t> hmac_sha256(
        const std::vector<uint8_t>& key,
        const std::vector<uint8_t>& data
    );

    /// Constants
    static constexpr size_t SHA256_DIGEST_LENGTH = 32;
    static constexpr size_t MAX_OUTPUT_LENGTH = 255 * SHA256_DIGEST_LENGTH; // 8160 bytes
};

} // namespace security
} // namespace emma

#endif // SWORDCOMM_HKDF_H
