//
//  liboqs_wrapper.h
//  EMMA SecurityKit - liboqs Integration
//
//  iOS-compatible wrapper for liboqs (Open Quantum Safe)
//  Provides production ML-KEM-1024 and ML-DSA-87 implementations
//

#ifndef EMMA_LIBOQS_WRAPPER_H
#define EMMA_LIBOQS_WRAPPER_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// MARK: - ML-KEM-1024 (FIPS 203) - Key Encapsulation
// ============================================================================

/// ML-KEM-1024 algorithm identifier
#define LIBOQS_KEM_ML_KEM_1024 "ML-KEM-1024"

/// ML-KEM-1024 key and ciphertext sizes (NIST FIPS 203)
#define LIBOQS_ML_KEM_1024_PUBLIC_KEY_BYTES    1568
#define LIBOQS_ML_KEM_1024_SECRET_KEY_BYTES    3168
#define LIBOQS_ML_KEM_1024_CIPHERTEXT_BYTES    1568
#define LIBOQS_ML_KEM_1024_SHARED_SECRET_BYTES 32

/// Generate ML-KEM-1024 keypair
/// @param public_key Output buffer for public key (must be 1568 bytes)
/// @param secret_key Output buffer for secret key (must be 3168 bytes)
/// @return 0 on success, non-zero on failure
int liboqs_ml_kem_1024_keypair(
    uint8_t *public_key,
    uint8_t *secret_key
);

/// ML-KEM-1024 encapsulation - create shared secret and ciphertext
/// @param ciphertext Output buffer for ciphertext (must be 1568 bytes)
/// @param shared_secret Output buffer for shared secret (must be 32 bytes)
/// @param public_key Input public key (must be 1568 bytes)
/// @return 0 on success, non-zero on failure
int liboqs_ml_kem_1024_encapsulate(
    uint8_t *ciphertext,
    uint8_t *shared_secret,
    const uint8_t *public_key
);

/// ML-KEM-1024 decapsulation - recover shared secret from ciphertext
/// @param shared_secret Output buffer for shared secret (must be 32 bytes)
/// @param ciphertext Input ciphertext (must be 1568 bytes)
/// @param secret_key Input secret key (must be 3168 bytes)
/// @return 0 on success, non-zero on failure
int liboqs_ml_kem_1024_decapsulate(
    uint8_t *shared_secret,
    const uint8_t *ciphertext,
    const uint8_t *secret_key
);

// ============================================================================
// MARK: - ML-DSA-87 (FIPS 204) - Digital Signatures
// ============================================================================

/// ML-DSA-87 algorithm identifier
#define LIBOQS_SIG_ML_DSA_87 "ML-DSA-87"

/// ML-DSA-87 key and signature sizes (NIST FIPS 204)
#define LIBOQS_ML_DSA_87_PUBLIC_KEY_BYTES  2592
#define LIBOQS_ML_DSA_87_SECRET_KEY_BYTES  4896
#define LIBOQS_ML_DSA_87_SIGNATURE_BYTES   4627

/// Generate ML-DSA-87 keypair
/// @param public_key Output buffer for public key (must be 2592 bytes)
/// @param secret_key Output buffer for secret key (must be 4896 bytes)
/// @return 0 on success, non-zero on failure
int liboqs_ml_dsa_87_keypair(
    uint8_t *public_key,
    uint8_t *secret_key
);

/// ML-DSA-87 signature generation
/// @param signature Output buffer for signature (must be 4627 bytes)
/// @param signature_len Output actual signature length
/// @param message Input message to sign
/// @param message_len Length of message
/// @param secret_key Input secret key (must be 4896 bytes)
/// @return 0 on success, non-zero on failure
int liboqs_ml_dsa_87_sign(
    uint8_t *signature,
    size_t *signature_len,
    const uint8_t *message,
    size_t message_len,
    const uint8_t *secret_key
);

/// ML-DSA-87 signature verification
/// @param message Input message that was signed
/// @param message_len Length of message
/// @param signature Input signature to verify
/// @param signature_len Length of signature
/// @param public_key Input public key (must be 2592 bytes)
/// @return 0 on success (valid signature), non-zero on failure (invalid)
int liboqs_ml_dsa_87_verify(
    const uint8_t *message,
    size_t message_len,
    const uint8_t *signature,
    size_t signature_len,
    const uint8_t *public_key
);

// ============================================================================
// MARK: - Library Initialization
// ============================================================================

/// Initialize liboqs library (call once at startup)
/// @return true on success, false on failure
bool liboqs_init(void);

/// Cleanup liboqs library (call at shutdown)
void liboqs_cleanup(void);

/// Get liboqs version string
/// @return Version string (e.g., "0.10.1")
const char* liboqs_version(void);

/// Check if ML-KEM-1024 is enabled in this build
/// @return true if available, false otherwise
bool liboqs_ml_kem_1024_enabled(void);

/// Check if ML-DSA-87 is enabled in this build
/// @return true if available, false otherwise
bool liboqs_ml_dsa_87_enabled(void);

#ifdef __cplusplus
}
#endif

#endif // EMMA_LIBOQS_WRAPPER_H
