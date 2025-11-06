//
//  EMSecurityKit.h
//  EMMA Security Kit
//
//  Objective-C bridge for C++ security components
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Threat Analysis

@interface EMThreatAnalysis : NSObject

@property (nonatomic, assign, readonly) float threatLevel;
@property (nonatomic, assign, readonly) float hypervisorConfidence;
@property (nonatomic, assign, readonly) BOOL timingAnomalyDetected;
@property (nonatomic, assign, readonly) BOOL cacheAnomalyDetected;
@property (nonatomic, assign, readonly) BOOL perfCounterBlocked;
@property (nonatomic, assign, readonly) BOOL memoryAnomalyDetected;
@property (nonatomic, assign, readonly) uint64_t analysisTimestamp;

@end

// MARK: - EL2 Detector

@interface EMEL2Detector : NSObject

+ (instancetype)sharedDetector;

- (BOOL)initialize;
- (nullable EMThreatAnalysis *)analyzeThreat;

@end

// MARK: - Memory Scrambler

@interface EMMemoryScrambler : NSObject

+ (void)secureWipeData:(NSMutableData *)data;
+ (void)scrambleData:(NSMutableData *)data;
+ (void)fillAvailableRAMWithPercent:(int)fillPercent;
+ (void)createDecoyPatternsWithSizeMB:(size_t)sizeMB;

@end

// MARK: - Timing Obfuscation

@interface EMTimingObfuscation : NSObject

+ (void)randomDelayMinUs:(int)minUs maxUs:(int)maxUs;
+ (void)exponentialDelayMeanUs:(int)meanUs;
+ (void)executeWithObfuscation:(void (^)(void))block chaosPercent:(int)chaosPercent;
+ (void)addTimingNoiseIntensityPercent:(int)intensityPercent;
+ (void)jitterSleepMs:(int)baseMs jitterPercent:(int)jitterPercent;

@end

// MARK: - Cache Operations

@interface EMCacheOperations : NSObject

+ (void)poisonCacheIntensityPercent:(int)intensityPercent;
+ (void)flushCacheRangeWithPointer:(void *)addr size:(size_t)size;
+ (void)prefetchCacheRangeWithPointer:(void *)addr size:(size_t)size;
+ (void)fillCacheWithNoiseSizeKB:(size_t)sizeKB;

@end

// MARK: - ML-KEM-1024 (NIST FIPS 203 - Post-Quantum Key Encapsulation)

@interface EMMLKEMKeyPair : NSObject

@property (nonatomic, strong, readonly) NSData *publicKey;  // 1568 bytes
@property (nonatomic, strong, readonly) NSData *secretKey;  // 3168 bytes

@end

@interface EMMLKEMEncapsulationResult : NSObject

@property (nonatomic, strong, readonly) NSData *ciphertext;    // 1568 bytes
@property (nonatomic, strong, readonly) NSData *sharedSecret;  // 32 bytes

@end

@interface EMMLKEM1024 : NSObject

+ (nullable EMMLKEMKeyPair *)generateKeypair;
+ (nullable EMMLKEMEncapsulationResult *)encapsulateWithPublicKey:(NSData *)publicKey;
+ (nullable NSData *)decapsulateWithCiphertext:(NSData *)ciphertext secretKey:(NSData *)secretKey;

@end

// MARK: - ML-DSA-87 (NIST FIPS 204 - Post-Quantum Digital Signatures)

@interface EMMLDSAKeyPair : NSObject

@property (nonatomic, strong, readonly) NSData *publicKey;  // 2592 bytes
@property (nonatomic, strong, readonly) NSData *secretKey;  // 4896 bytes

@end

@interface EMMLDSASignature : NSObject

@property (nonatomic, strong, readonly) NSData *signature;  // 4627 bytes

@end

@interface EMMLDSA87 : NSObject

+ (nullable EMMLDSAKeyPair *)generateKeypair;
+ (nullable EMMLDSASignature *)signMessage:(NSData *)message withSecretKey:(NSData *)secretKey;
+ (BOOL)verifyMessage:(NSData *)message signature:(NSData *)signature withPublicKey:(NSData *)publicKey;

@end

// MARK: - Backward Compatibility (deprecated - use ML-KEM instead)

@interface EMKyberKeyPair : NSObject
@property (nonatomic, strong, readonly) NSData *publicKey;  // 1568 bytes
@property (nonatomic, strong, readonly) NSData *secretKey;  // 3168 bytes
@end

@interface EMKyberEncapsulationResult : NSObject
@property (nonatomic, strong, readonly) NSData *ciphertext;    // 1568 bytes
@property (nonatomic, strong, readonly) NSData *sharedSecret;  // 32 bytes
@end

@interface EMKyber1024 : NSObject
+ (nullable EMKyberKeyPair *)generateKeypair __attribute__((deprecated("Use EMMLKEM1024 instead - Kyber is now standardized as ML-KEM")));
+ (nullable EMKyberEncapsulationResult *)encapsulateWithPublicKey:(NSData *)publicKey __attribute__((deprecated("Use EMMLKEM1024 instead")));
+ (nullable NSData *)decapsulateWithCiphertext:(NSData *)ciphertext secretKey:(NSData *)secretKey __attribute__((deprecated("Use EMMLKEM1024 instead")));
@end

NS_ASSUME_NONNULL_END
