

/// All dependencies on external libraries used for cryptography should be hidden behind CryptoTools methods.
/// That way, changing to a different library affects only one part of the system.

@interface CryptoTools : NSObject

/// Returns a secure random 16-bit unsigned integer.
+ (uint16_t)generateSecureRandomUInt16;

/// Returns a secure random 32-bit unsigned integer.
+ (uint32_t)generateSecureRandomUInt32;

/// Returns data composed of 'length' cryptographically unpredictable bytes sampled uniformly from [0, 256).
+ (NSData *)generateSecureRandomData:(NSUInteger)length;

/// Returns the token included as part of HTTP OTP authentication.
+ (NSString *)computeOtpWithPassword:(NSString *)password andCounter:(int64_t)counter;

@end

@interface NSData (CryptoTools)

- (NSData *)hashWithSha256;

- (NSData *)hmacWithSha1WithKey:(NSData *)key;
- (NSData *)hmacWithSha256WithKey:(NSData *)key;

- (NSData *)encryptWithAesInCipherFeedbackModeWithKey:(NSData *)key andIv:(NSData *)iv;
- (NSData *)decryptWithAesInCipherFeedbackModeWithKey:(NSData *)key andIv:(NSData *)iv;

- (NSData *)encryptWithAesInCipherBlockChainingModeWithPkcs7PaddingWithKey:(NSData *)key andIv:(NSData *)iv;
- (NSData *)decryptWithAesInCipherBlockChainingModeWithPkcs7PaddingWithKey:(NSData *)key andIv:(NSData *)iv;

- (NSData *)encryptWithAesInCounterModeWithKey:(NSData *)key andIv:(NSData *)iv;
- (NSData *)decryptWithAesInCounterModeWithKey:(NSData *)key andIv:(NSData *)iv;

/// Determines if two data vectors contain the same information.
/// Avoids short-circuiting or data-dependent branches, so that early returns can't be used to infer where the
/// difference is.
/// Returns early if data is of different length.
- (bool)isEqualToData_TimingSafe:(NSData *)other;

@end
