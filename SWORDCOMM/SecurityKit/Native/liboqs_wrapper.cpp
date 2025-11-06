//
//  liboqs_wrapper.cpp
//  SWORDCOMM SecurityKit - liboqs Integration
//
//  iOS-compatible wrapper implementation for liboqs
//

#include "liboqs_wrapper.h"
#include "ios_platform.h"
#include <string.h>

// Check if liboqs is available at compile time
#ifdef HAVE_LIBOQS
    #include <oqs/oqs.h>
    #define LIBOQS_AVAILABLE 1
#else
    #define LIBOQS_AVAILABLE 0
#endif

// ============================================================================
// MARK: - Library Initialization
// ============================================================================

bool liboqs_init(void) {
#if LIBOQS_AVAILABLE
    SWORDCOMM_LOG_INFO("liboqs initialization - version: %s", OQS_VERSION);

    // Verify ML-KEM-1024 is available
    if (!OQS_KEM_alg_is_enabled(OQS_KEM_alg_ml_kem_1024)) {
        SWORDCOMM_LOG_ERROR("ML-KEM-1024 not enabled in liboqs build");
        return false;
    }

    // Verify ML-DSA-87 is available
    if (!OQS_SIG_alg_is_enabled(OQS_SIG_alg_ml_dsa_87)) {
        SWORDCOMM_LOG_ERROR("ML-DSA-87 not enabled in liboqs build");
        return false;
    }

    SWORDCOMM_LOG_INFO("liboqs initialized successfully - ML-KEM-1024 and ML-DSA-87 enabled");
    return true;
#else
    SWORDCOMM_LOG_WARN("liboqs NOT COMPILED - using stub implementations");
    SWORDCOMM_LOG_WARN("To enable production crypto, build with HAVE_LIBOQS=1");
    return true; // Return true for stub mode
#endif
}

void liboqs_cleanup(void) {
#if LIBOQS_AVAILABLE
    // liboqs doesn't require explicit cleanup, but we log it
    SWORDCOMM_LOG_INFO("liboqs cleanup");
#endif
}

const char* liboqs_version(void) {
#if LIBOQS_AVAILABLE
    return OQS_VERSION;
#else
    return "STUB-MODE";
#endif
}

bool liboqs_ml_kem_1024_enabled(void) {
#if LIBOQS_AVAILABLE
    return OQS_KEM_alg_is_enabled(OQS_KEM_alg_ml_kem_1024);
#else
    return false;
#endif
}

bool liboqs_ml_dsa_87_enabled(void) {
#if LIBOQS_AVAILABLE
    return OQS_SIG_alg_is_enabled(OQS_SIG_alg_ml_dsa_87);
#else
    return false;
#endif
}

// ============================================================================
// MARK: - ML-KEM-1024 Implementation
// ============================================================================

int liboqs_ml_kem_1024_keypair(uint8_t *public_key, uint8_t *secret_key) {
    if (!public_key || !secret_key) {
        SWORDCOMM_LOG_ERROR("NULL pointer passed to ml_kem_1024_keypair");
        return -1;
    }

#if LIBOQS_AVAILABLE
    OQS_KEM *kem = OQS_KEM_new(OQS_KEM_alg_ml_kem_1024);
    if (!kem) {
        SWORDCOMM_LOG_ERROR("Failed to create ML-KEM-1024 context");
        return -1;
    }

    // Verify sizes match our constants
    if (kem->length_public_key != LIBOQS_ML_KEM_1024_PUBLIC_KEY_BYTES) {
        SWORDCOMM_LOG_ERROR("ML-KEM-1024 public key size mismatch: %zu != %d",
                      kem->length_public_key, LIBOQS_ML_KEM_1024_PUBLIC_KEY_BYTES);
        OQS_KEM_free(kem);
        return -1;
    }

    if (kem->length_secret_key != LIBOQS_ML_KEM_1024_SECRET_KEY_BYTES) {
        SWORDCOMM_LOG_ERROR("ML-KEM-1024 secret key size mismatch: %zu != %d",
                      kem->length_secret_key, LIBOQS_ML_KEM_1024_SECRET_KEY_BYTES);
        OQS_KEM_free(kem);
        return -1;
    }

    // Generate keypair
    OQS_STATUS status = OQS_KEM_keypair(kem, public_key, secret_key);
    OQS_KEM_free(kem);

    if (status != OQS_SUCCESS) {
        SWORDCOMM_LOG_ERROR("ML-KEM-1024 keypair generation failed");
        return -1;
    }

    SWORDCOMM_LOG_INFO("ML-KEM-1024 keypair generated successfully");
    return 0;
#else
    // STUB IMPLEMENTATION - DO NOT USE IN PRODUCTION
    SWORDCOMM_LOG_WARN("STUB: ML-KEM-1024 keypair generation (NOT SECURE)");

    if (!secure_random_bytes(public_key, LIBOQS_ML_KEM_1024_PUBLIC_KEY_BYTES) ||
        !secure_random_bytes(secret_key, LIBOQS_ML_KEM_1024_SECRET_KEY_BYTES)) {
        SWORDCOMM_LOG_ERROR("Failed to generate random stub keys");
        return -1;
    }

    return 0;
#endif
}

int liboqs_ml_kem_1024_encapsulate(
    uint8_t *ciphertext,
    uint8_t *shared_secret,
    const uint8_t *public_key
) {
    if (!ciphertext || !shared_secret || !public_key) {
        SWORDCOMM_LOG_ERROR("NULL pointer passed to ml_kem_1024_encapsulate");
        return -1;
    }

#if LIBOQS_AVAILABLE
    OQS_KEM *kem = OQS_KEM_new(OQS_KEM_alg_ml_kem_1024);
    if (!kem) {
        SWORDCOMM_LOG_ERROR("Failed to create ML-KEM-1024 context");
        return -1;
    }

    OQS_STATUS status = OQS_KEM_encaps(kem, ciphertext, shared_secret, public_key);
    OQS_KEM_free(kem);

    if (status != OQS_SUCCESS) {
        SWORDCOMM_LOG_ERROR("ML-KEM-1024 encapsulation failed");
        return -1;
    }

    SWORDCOMM_LOG_DEBUG("ML-KEM-1024 encapsulation successful");
    return 0;
#else
    // STUB IMPLEMENTATION - DO NOT USE IN PRODUCTION
    SWORDCOMM_LOG_WARN("STUB: ML-KEM-1024 encapsulation (NOT SECURE)");

    if (!secure_random_bytes(ciphertext, LIBOQS_ML_KEM_1024_CIPHERTEXT_BYTES) ||
        !secure_random_bytes(shared_secret, LIBOQS_ML_KEM_1024_SHARED_SECRET_BYTES)) {
        SWORDCOMM_LOG_ERROR("Failed to generate random stub encapsulation");
        return -1;
    }

    return 0;
#endif
}

int liboqs_ml_kem_1024_decapsulate(
    uint8_t *shared_secret,
    const uint8_t *ciphertext,
    const uint8_t *secret_key
) {
    if (!shared_secret || !ciphertext || !secret_key) {
        SWORDCOMM_LOG_ERROR("NULL pointer passed to ml_kem_1024_decapsulate");
        return -1;
    }

#if LIBOQS_AVAILABLE
    OQS_KEM *kem = OQS_KEM_new(OQS_KEM_alg_ml_kem_1024);
    if (!kem) {
        SWORDCOMM_LOG_ERROR("Failed to create ML-KEM-1024 context");
        return -1;
    }

    OQS_STATUS status = OQS_KEM_decaps(kem, shared_secret, ciphertext, secret_key);
    OQS_KEM_free(kem);

    if (status != OQS_SUCCESS) {
        SWORDCOMM_LOG_ERROR("ML-KEM-1024 decapsulation failed");
        return -1;
    }

    SWORDCOMM_LOG_DEBUG("ML-KEM-1024 decapsulation successful");
    return 0;
#else
    // STUB IMPLEMENTATION - DO NOT USE IN PRODUCTION
    SWORDCOMM_LOG_WARN("STUB: ML-KEM-1024 decapsulation (NOT SECURE)");

    // In stub mode, we can't actually decrypt, so just return random data
    // This will NOT work for real communication!
    if (!secure_random_bytes(shared_secret, LIBOQS_ML_KEM_1024_SHARED_SECRET_BYTES)) {
        SWORDCOMM_LOG_ERROR("Failed to generate random stub shared secret");
        return -1;
    }

    return 0;
#endif
}

// ============================================================================
// MARK: - ML-DSA-87 Implementation
// ============================================================================

int liboqs_ml_dsa_87_keypair(uint8_t *public_key, uint8_t *secret_key) {
    if (!public_key || !secret_key) {
        SWORDCOMM_LOG_ERROR("NULL pointer passed to ml_dsa_87_keypair");
        return -1;
    }

#if LIBOQS_AVAILABLE
    OQS_SIG *sig = OQS_SIG_new(OQS_SIG_alg_ml_dsa_87);
    if (!sig) {
        SWORDCOMM_LOG_ERROR("Failed to create ML-DSA-87 context");
        return -1;
    }

    // Verify sizes match our constants
    if (sig->length_public_key != LIBOQS_ML_DSA_87_PUBLIC_KEY_BYTES) {
        SWORDCOMM_LOG_ERROR("ML-DSA-87 public key size mismatch: %zu != %d",
                      sig->length_public_key, LIBOQS_ML_DSA_87_PUBLIC_KEY_BYTES);
        OQS_SIG_free(sig);
        return -1;
    }

    if (sig->length_secret_key != LIBOQS_ML_DSA_87_SECRET_KEY_BYTES) {
        SWORDCOMM_LOG_ERROR("ML-DSA-87 secret key size mismatch: %zu != %d",
                      sig->length_secret_key, LIBOQS_ML_DSA_87_SECRET_KEY_BYTES);
        OQS_SIG_free(sig);
        return -1;
    }

    // Generate keypair
    OQS_STATUS status = OQS_SIG_keypair(sig, public_key, secret_key);
    OQS_SIG_free(sig);

    if (status != OQS_SUCCESS) {
        SWORDCOMM_LOG_ERROR("ML-DSA-87 keypair generation failed");
        return -1;
    }

    SWORDCOMM_LOG_INFO("ML-DSA-87 keypair generated successfully");
    return 0;
#else
    // STUB IMPLEMENTATION - DO NOT USE IN PRODUCTION
    SWORDCOMM_LOG_WARN("STUB: ML-DSA-87 keypair generation (NOT SECURE)");

    if (!secure_random_bytes(public_key, LIBOQS_ML_DSA_87_PUBLIC_KEY_BYTES) ||
        !secure_random_bytes(secret_key, LIBOQS_ML_DSA_87_SECRET_KEY_BYTES)) {
        SWORDCOMM_LOG_ERROR("Failed to generate random stub keys");
        return -1;
    }

    return 0;
#endif
}

int liboqs_ml_dsa_87_sign(
    uint8_t *signature,
    size_t *signature_len,
    const uint8_t *message,
    size_t message_len,
    const uint8_t *secret_key
) {
    if (!signature || !signature_len || !message || !secret_key) {
        SWORDCOMM_LOG_ERROR("NULL pointer passed to ml_dsa_87_sign");
        return -1;
    }

#if LIBOQS_AVAILABLE
    OQS_SIG *sig = OQS_SIG_new(OQS_SIG_alg_ml_dsa_87);
    if (!sig) {
        SWORDCOMM_LOG_ERROR("Failed to create ML-DSA-87 context");
        return -1;
    }

    OQS_STATUS status = OQS_SIG_sign(sig, signature, signature_len, message, message_len, secret_key);
    OQS_SIG_free(sig);

    if (status != OQS_SUCCESS) {
        SWORDCOMM_LOG_ERROR("ML-DSA-87 signature generation failed");
        return -1;
    }

    SWORDCOMM_LOG_DEBUG("ML-DSA-87 signature generated (%zu bytes)", *signature_len);
    return 0;
#else
    // STUB IMPLEMENTATION - DO NOT USE IN PRODUCTION
    SWORDCOMM_LOG_WARN("STUB: ML-DSA-87 signing (NOT SECURE)");

    *signature_len = LIBOQS_ML_DSA_87_SIGNATURE_BYTES;
    if (!secure_random_bytes(signature, LIBOQS_ML_DSA_87_SIGNATURE_BYTES)) {
        SWORDCOMM_LOG_ERROR("Failed to generate random stub signature");
        return -1;
    }

    return 0;
#endif
}

int liboqs_ml_dsa_87_verify(
    const uint8_t *message,
    size_t message_len,
    const uint8_t *signature,
    size_t signature_len,
    const uint8_t *public_key
) {
    if (!message || !signature || !public_key) {
        SWORDCOMM_LOG_ERROR("NULL pointer passed to ml_dsa_87_verify");
        return -1;
    }

#if LIBOQS_AVAILABLE
    OQS_SIG *sig = OQS_SIG_new(OQS_SIG_alg_ml_dsa_87);
    if (!sig) {
        SWORDCOMM_LOG_ERROR("Failed to create ML-DSA-87 context");
        return -1;
    }

    OQS_STATUS status = OQS_SIG_verify(sig, message, message_len, signature, signature_len, public_key);
    OQS_SIG_free(sig);

    if (status != OQS_SUCCESS) {
        SWORDCOMM_LOG_WARN("ML-DSA-87 signature verification failed");
        return -1;
    }

    SWORDCOMM_LOG_DEBUG("ML-DSA-87 signature verified successfully");
    return 0;
#else
    // STUB IMPLEMENTATION - DO NOT USE IN PRODUCTION
    SWORDCOMM_LOG_WARN("STUB: ML-DSA-87 verification (ALWAYS SUCCEEDS - NOT SECURE)");

    // In stub mode, we can't actually verify, so always return success
    // This is INSECURE and should never be used in production!
    return 0;
#endif
}
