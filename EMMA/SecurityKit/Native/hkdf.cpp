//
//  hkdf.cpp
//  EMMA SecurityKit - HKDF-SHA256 Implementation
//
//  RFC 5869 HKDF implementation for iOS using CommonCrypto
//

#include "hkdf.h"
#include "ios_platform.h"
#include <CommonCrypto/CommonHMAC.h>
#include <stdexcept>
#include <algorithm>

namespace emma {
namespace security {

// ============================================================================
// HKDF-Extract (RFC 5869 Section 2.2)
// ============================================================================

std::vector<uint8_t> HKDF::extract(
    const std::vector<uint8_t>& ikm,
    const std::vector<uint8_t>& salt
) {
    if (ikm.empty()) {
        throw std::invalid_argument("HKDF: Input keying material cannot be empty");
    }

    // If salt is empty, use a string of zeros
    std::vector<uint8_t> actual_salt = salt;
    if (actual_salt.empty()) {
        actual_salt.resize(SHA256_DIGEST_LENGTH, 0);
    }

    // PRK = HMAC-SHA256(salt, IKM)
    std::vector<uint8_t> prk = hmac_sha256(actual_salt, ikm);

    EMMA_LOG_DEBUG("HKDF-Extract: IKM=%zu bytes, salt=%zu bytes -> PRK=32 bytes",
                   ikm.size(), salt.size());

    return prk;
}

// ============================================================================
// HKDF-Expand (RFC 5869 Section 2.3)
// ============================================================================

std::vector<uint8_t> HKDF::expand(
    const std::vector<uint8_t>& prk,
    const std::vector<uint8_t>& info,
    size_t length
) {
    if (prk.size() < SHA256_DIGEST_LENGTH) {
        throw std::invalid_argument("HKDF: PRK must be at least 32 bytes");
    }

    if (length == 0) {
        throw std::invalid_argument("HKDF: Output length must be greater than 0");
    }

    if (length > MAX_OUTPUT_LENGTH) {
        throw std::invalid_argument("HKDF: Requested length exceeds maximum (8160 bytes)");
    }

    // Calculate number of iterations needed
    size_t n = (length + SHA256_DIGEST_LENGTH - 1) / SHA256_DIGEST_LENGTH;

    std::vector<uint8_t> okm; // Output Keying Material
    okm.reserve(n * SHA256_DIGEST_LENGTH);

    std::vector<uint8_t> t_prev; // T(i-1)

    for (size_t i = 1; i <= n; i++) {
        // T(i) = HMAC-SHA256(PRK, T(i-1) | info | i)
        std::vector<uint8_t> data;
        data.reserve(t_prev.size() + info.size() + 1);

        // Append T(i-1) if not first iteration
        if (!t_prev.empty()) {
            data.insert(data.end(), t_prev.begin(), t_prev.end());
        }

        // Append info
        if (!info.empty()) {
            data.insert(data.end(), info.begin(), info.end());
        }

        // Append counter (1-indexed)
        data.push_back(static_cast<uint8_t>(i));

        // Compute HMAC
        std::vector<uint8_t> t = hmac_sha256(prk, data);

        // Append to output
        okm.insert(okm.end(), t.begin(), t.end());

        // Save for next iteration
        t_prev = t;
    }

    // Trim to requested length
    okm.resize(length);

    EMMA_LOG_DEBUG("HKDF-Expand: PRK=32 bytes, info=%zu bytes, iterations=%zu -> OKM=%zu bytes",
                   info.size(), n, length);

    return okm;
}

// ============================================================================
// Full HKDF (Extract + Expand)
// ============================================================================

std::vector<uint8_t> HKDF::derive_key(
    const std::vector<uint8_t>& ikm,
    const std::vector<uint8_t>& salt,
    const std::vector<uint8_t>& info,
    size_t length
) {
    // Extract
    std::vector<uint8_t> prk = extract(ikm, salt);

    // Expand
    std::vector<uint8_t> okm = expand(prk, info, length);

    EMMA_LOG_INFO("HKDF: Derived %zu bytes from %zu-byte IKM", length, ikm.size());

    return okm;
}

// ============================================================================
// Convenience Functions
// ============================================================================

std::vector<uint8_t> HKDF::derive_aes_key(
    const std::vector<uint8_t>& shared_secret,
    const std::vector<uint8_t>& info
) {
    if (shared_secret.size() != 32) {
        throw std::invalid_argument("HKDF: ML-KEM shared secret must be 32 bytes");
    }

    // Derive 32-byte AES-256 key
    return derive_key(shared_secret, {}, info, 32);
}

std::vector<std::vector<uint8_t>> HKDF::derive_keys(
    const std::vector<uint8_t>& shared_secret,
    const std::vector<uint8_t>& info,
    size_t key_count,
    size_t key_length
) {
    if (key_count == 0) {
        throw std::invalid_argument("HKDF: key_count must be greater than 0");
    }

    size_t total_length = key_count * key_length;

    // Derive all key material at once
    std::vector<uint8_t> okm = derive_key(shared_secret, {}, info, total_length);

    // Split into individual keys
    std::vector<std::vector<uint8_t>> keys;
    keys.reserve(key_count);

    for (size_t i = 0; i < key_count; i++) {
        size_t offset = i * key_length;
        std::vector<uint8_t> key(okm.begin() + offset, okm.begin() + offset + key_length);
        keys.push_back(key);
    }

    EMMA_LOG_INFO("HKDF: Derived %zu keys of %zu bytes each", key_count, key_length);

    return keys;
}

// ============================================================================
// HMAC-SHA256 Implementation using CommonCrypto
// ============================================================================

std::vector<uint8_t> HKDF::hmac_sha256(
    const std::vector<uint8_t>& key,
    const std::vector<uint8_t>& data
) {
    std::vector<uint8_t> mac(SHA256_DIGEST_LENGTH);

    CCHmac(
        kCCHmacAlgSHA256,
        key.data(),
        key.size(),
        data.data(),
        data.size(),
        mac.data()
    );

    return mac;
}

} // namespace security
} // namespace emma
