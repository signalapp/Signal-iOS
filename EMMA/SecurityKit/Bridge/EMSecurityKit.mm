//
//  EMSecurityKit.mm
//  EMMA Security Kit
//
//  Objective-C++ bridge implementation
//

#import "EMSecurityKit.h"

// Include C++ headers
#include "../Native/el2_detector.h"
#include "../Native/memory_scrambler.h"
#include "../Native/timing_obfuscation.h"
#include "../Native/cache_operations.h"
#include "../Native/nist_pqc.h"

using namespace emma::security;

// MARK: - Threat Analysis

@interface EMThreatAnalysis ()

- (instancetype)initWithCppAnalysis:(const ThreatAnalysis&)analysis;

@end

@implementation EMThreatAnalysis

- (instancetype)initWithCppAnalysis:(const ThreatAnalysis&)analysis {
    if (self = [super init]) {
        _threatLevel = analysis.threat_level;
        _hypervisorConfidence = analysis.hypervisor_confidence;
        _timingAnomalyDetected = analysis.timing_anomaly_detected;
        _cacheAnomalyDetected = analysis.cache_anomaly_detected;
        _perfCounterBlocked = analysis.perf_counter_blocked;
        _memoryAnomalyDetected = analysis.memory_anomaly_detected;
        _analysisTimestamp = analysis.analysis_timestamp;
    }
    return self;
}

@end

// MARK: - EL2 Detector

@interface EMEL2Detector () {
    EL2Detector *_cppDetector;
}
@end

@implementation EMEL2Detector

+ (instancetype)sharedDetector {
    static EMEL2Detector *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[EMEL2Detector alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if (self = [super init]) {
        _cppDetector = new EL2Detector();
    }
    return self;
}

- (void)dealloc {
    if (_cppDetector) {
        delete _cppDetector;
        _cppDetector = nullptr;
    }
}

- (BOOL)initialize {
    if (!_cppDetector) {
        return NO;
    }
    return _cppDetector->initialize();
}

- (nullable EMThreatAnalysis *)analyzeThreat {
    if (!_cppDetector) {
        return nil;
    }

    ThreatAnalysis analysis = _cppDetector->analyze_threat();
    return [[EMThreatAnalysis alloc] initWithCppAnalysis:analysis];
}

@end

// MARK: - Memory Scrambler

@implementation EMMemoryScrambler

+ (void)secureWipeData:(NSMutableData *)data {
    if (!data || data.length == 0) {
        return;
    }

    MemoryScrambler::secure_wipe(data.mutableBytes, data.length);
}

+ (void)scrambleData:(NSMutableData *)data {
    if (!data || data.length == 0) {
        return;
    }

    MemoryScrambler::scramble_memory(data.mutableBytes, data.length);
}

+ (void)fillAvailableRAMWithPercent:(int)fillPercent {
    MemoryScrambler::fill_available_ram(fillPercent);
}

+ (void)createDecoyPatternsWithSizeMB:(size_t)sizeMB {
    MemoryScrambler::create_decoy_patterns(sizeMB);
}

@end

// MARK: - Timing Obfuscation

@implementation EMTimingObfuscation

+ (void)randomDelayMinUs:(int)minUs maxUs:(int)maxUs {
    TimingObfuscation::random_delay_us(minUs, maxUs);
}

+ (void)exponentialDelayMeanUs:(int)meanUs {
    TimingObfuscation::exponential_delay_us(meanUs);
}

+ (void)executeWithObfuscation:(void (^)(void))block chaosPercent:(int)chaosPercent {
    if (!block) {
        return;
    }

    TimingObfuscation::execute_with_obfuscation([block]() {
        block();
    }, chaosPercent);
}

+ (void)addTimingNoiseIntensityPercent:(int)intensityPercent {
    TimingObfuscation::add_timing_noise(intensityPercent);
}

+ (void)jitterSleepMs:(int)baseMs jitterPercent:(int)jitterPercent {
    TimingObfuscation::jitter_sleep_ms(baseMs, jitterPercent);
}

@end

// MARK: - Cache Operations

@implementation EMCacheOperations

+ (void)poisonCacheIntensityPercent:(int)intensityPercent {
    CacheOperations::poison_cache(intensityPercent);
}

+ (void)flushCacheRangeWithPointer:(void *)addr size:(size_t)size {
    CacheOperations::flush_cache_range(addr, size);
}

+ (void)prefetchCacheRangeWithPointer:(void *)addr size:(size_t)size {
    CacheOperations::prefetch_cache_range(addr, size);
}

+ (void)fillCacheWithNoiseSizeKB:(size_t)sizeKB {
    CacheOperations::fill_cache_with_noise(sizeKB);
}

@end

// MARK: - Kyber-1024

@implementation EMKyberKeyPair

- (instancetype)initWithPublicKey:(NSData *)publicKey secretKey:(NSData *)secretKey {
    if (self = [super init]) {
        _publicKey = [publicKey copy];
        _secretKey = [secretKey copy];
    }
    return self;
}

@end

@implementation EMKyberEncapsulationResult

- (instancetype)initWithCiphertext:(NSData *)ciphertext sharedSecret:(NSData *)sharedSecret {
    if (self = [super init]) {
        _ciphertext = [ciphertext copy];
        _sharedSecret = [sharedSecret copy];
    }
    return self;
}

@end

@implementation EMKyber1024

+ (nullable EMKyberKeyPair *)generateKeypair {
    @try {
        KeyPair kp = Kyber1024::generate_keypair();

        NSData *publicKey = [NSData dataWithBytes:kp.public_key.data()
                                          length:kp.public_key.size()];
        NSData *secretKey = [NSData dataWithBytes:kp.secret_key.data()
                                          length:kp.secret_key.size()];

        return [[EMKyberKeyPair alloc] initWithPublicKey:publicKey secretKey:secretKey];
    }
    @catch (NSException *exception) {
        NSLog(@"Kyber keypair generation failed: %@", exception);
        return nil;
    }
}

+ (nullable EMKyberEncapsulationResult *)encapsulateWithPublicKey:(NSData *)publicKey {
    if (!publicKey || publicKey.length != 1568) {
        return nil;
    }

    @try {
        std::vector<uint8_t> pk_vec((const uint8_t *)publicKey.bytes,
                                    (const uint8_t *)publicKey.bytes + publicKey.length);

        EncapsulationResult result = Kyber1024::encapsulate(pk_vec);

        NSData *ciphertext = [NSData dataWithBytes:result.ciphertext.data()
                                           length:result.ciphertext.size()];
        NSData *sharedSecret = [NSData dataWithBytes:result.shared_secret.data()
                                             length:result.shared_secret.size()];

        return [[EMKyberEncapsulationResult alloc] initWithCiphertext:ciphertext
                                                         sharedSecret:sharedSecret];
    }
    @catch (NSException *exception) {
        NSLog(@"Kyber encapsulation failed: %@", exception);
        return nil;
    }
}

+ (nullable NSData *)decapsulateWithCiphertext:(NSData *)ciphertext secretKey:(NSData *)secretKey {
    if (!ciphertext || ciphertext.length != 1568 || !secretKey || secretKey.length != 3168) {
        return nil;
    }

    @try {
        std::vector<uint8_t> ct_vec((const uint8_t *)ciphertext.bytes,
                                    (const uint8_t *)ciphertext.bytes + ciphertext.length);
        std::vector<uint8_t> sk_vec((const uint8_t *)secretKey.bytes,
                                    (const uint8_t *)secretKey.bytes + secretKey.length);

        std::vector<uint8_t> shared_secret = Kyber1024::decapsulate(ct_vec, sk_vec);

        return [NSData dataWithBytes:shared_secret.data() length:shared_secret.size()];
    }
    @catch (NSException *exception) {
        NSLog(@"Kyber decapsulation failed: %@", exception);
        return nil;
    }
}

@end

// MARK: - ML-KEM-1024 (NIST FIPS 203)

@implementation EMMLKEMKeyPair

- (instancetype)initWithPublicKey:(NSData *)publicKey secretKey:(NSData *)secretKey {
    if (self = [super init]) {
        _publicKey = [publicKey copy];
        _secretKey = [secretKey copy];
    }
    return self;
}

@end

@implementation EMMLKEMEncapsulationResult

- (instancetype)initWithCiphertext:(NSData *)ciphertext sharedSecret:(NSData *)sharedSecret {
    if (self = [super init]) {
        _ciphertext = [ciphertext copy];
        _sharedSecret = [sharedSecret copy];
    }
    return self;
}

@end

@implementation EMMLKEM1024

+ (nullable EMMLKEMKeyPair *)generateKeypair {
    @try {
        MLKEMKeyPair kp = MLKEM1024::generate_keypair();

        NSData *publicKey = [NSData dataWithBytes:kp.public_key.data()
                                          length:kp.public_key.size()];
        NSData *secretKey = [NSData dataWithBytes:kp.secret_key.data()
                                          length:kp.secret_key.size()];

        return [[EMMLKEMKeyPair alloc] initWithPublicKey:publicKey secretKey:secretKey];
    }
    @catch (NSException *exception) {
        NSLog(@"ML-KEM keypair generation failed: %@", exception);
        return nil;
    }
}

+ (nullable EMMLKEMEncapsulationResult *)encapsulateWithPublicKey:(NSData *)publicKey {
    if (!publicKey || publicKey.length != ML_KEM_1024_PUBLIC_KEY_SIZE) {
        return nil;
    }

    @try {
        std::vector<uint8_t> pk_vec((const uint8_t *)publicKey.bytes,
                                    (const uint8_t *)publicKey.bytes + publicKey.length);

        MLKEMEncapsulationResult result = MLKEM1024::encapsulate(pk_vec);

        NSData *ciphertext = [NSData dataWithBytes:result.ciphertext.data()
                                           length:result.ciphertext.size()];
        NSData *sharedSecret = [NSData dataWithBytes:result.shared_secret.data()
                                             length:result.shared_secret.size()];

        return [[EMMLKEMEncapsulationResult alloc] initWithCiphertext:ciphertext
                                                         sharedSecret:sharedSecret];
    }
    @catch (NSException *exception) {
        NSLog(@"ML-KEM encapsulation failed: %@", exception);
        return nil;
    }
}

+ (nullable NSData *)decapsulateWithCiphertext:(NSData *)ciphertext secretKey:(NSData *)secretKey {
    if (!ciphertext || ciphertext.length != ML_KEM_1024_CIPHERTEXT_SIZE ||
        !secretKey || secretKey.length != ML_KEM_1024_SECRET_KEY_SIZE) {
        return nil;
    }

    @try {
        std::vector<uint8_t> ct_vec((const uint8_t *)ciphertext.bytes,
                                    (const uint8_t *)ciphertext.bytes + ciphertext.length);
        std::vector<uint8_t> sk_vec((const uint8_t *)secretKey.bytes,
                                    (const uint8_t *)secretKey.bytes + secretKey.length);

        std::vector<uint8_t> shared_secret = MLKEM1024::decapsulate(ct_vec, sk_vec);

        return [NSData dataWithBytes:shared_secret.data() length:shared_secret.size()];
    }
    @catch (NSException *exception) {
        NSLog(@"ML-KEM decapsulation failed: %@", exception);
        return nil;
    }
}

@end

// MARK: - ML-DSA-87 (NIST FIPS 204)

@implementation EMMLDSAKeyPair

- (instancetype)initWithPublicKey:(NSData *)publicKey secretKey:(NSData *)secretKey {
    if (self = [super init]) {
        _publicKey = [publicKey copy];
        _secretKey = [secretKey copy];
    }
    return self;
}

@end

@implementation EMMLDSASignature

- (instancetype)initWithSignature:(NSData *)signature {
    if (self = [super init]) {
        _signature = [signature copy];
    }
    return self;
}

@end

@implementation EMMLDSA87

+ (nullable EMMLDSAKeyPair *)generateKeypair {
    @try {
        MLDSAKeyPair kp = MLDSA87::generate_keypair();

        NSData *publicKey = [NSData dataWithBytes:kp.public_key.data()
                                          length:kp.public_key.size()];
        NSData *secretKey = [NSData dataWithBytes:kp.secret_key.data()
                                          length:kp.secret_key.size()];

        return [[EMMLDSAKeyPair alloc] initWithPublicKey:publicKey secretKey:secretKey];
    }
    @catch (NSException *exception) {
        NSLog(@"ML-DSA keypair generation failed: %@", exception);
        return nil;
    }
}

+ (nullable EMMLDSASignature *)signMessage:(NSData *)message withSecretKey:(NSData *)secretKey {
    if (!message || message.length == 0 || !secretKey || secretKey.length != ML_DSA_87_SECRET_KEY_SIZE) {
        return nil;
    }

    @try {
        std::vector<uint8_t> msg_vec((const uint8_t *)message.bytes,
                                     (const uint8_t *)message.bytes + message.length);
        std::vector<uint8_t> sk_vec((const uint8_t *)secretKey.bytes,
                                    (const uint8_t *)secretKey.bytes + secretKey.length);

        MLDSASignature sig = MLDSA87::sign(msg_vec, sk_vec);

        NSData *signature = [NSData dataWithBytes:sig.signature.data()
                                          length:sig.signature.size()];

        return [[EMMLDSASignature alloc] initWithSignature:signature];
    }
    @catch (NSException *exception) {
        NSLog(@"ML-DSA signing failed: %@", exception);
        return nil;
    }
}

+ (BOOL)verifyMessage:(NSData *)message signature:(NSData *)signature withPublicKey:(NSData *)publicKey {
    if (!message || message.length == 0 ||
        !signature || signature.length != ML_DSA_87_SIGNATURE_SIZE ||
        !publicKey || publicKey.length != ML_DSA_87_PUBLIC_KEY_SIZE) {
        return NO;
    }

    @try {
        std::vector<uint8_t> msg_vec((const uint8_t *)message.bytes,
                                     (const uint8_t *)message.bytes + message.length);
        std::vector<uint8_t> sig_vec((const uint8_t *)signature.bytes,
                                     (const uint8_t *)signature.bytes + signature.length);
        std::vector<uint8_t> pk_vec((const uint8_t *)publicKey.bytes,
                                    (const uint8_t *)publicKey.bytes + publicKey.length);

        return MLDSA87::verify(msg_vec, sig_vec, pk_vec) ? YES : NO;
    }
    @catch (NSException *exception) {
        NSLog(@"ML-DSA verification failed: %@", exception);
        return NO;
    }
}

@end
