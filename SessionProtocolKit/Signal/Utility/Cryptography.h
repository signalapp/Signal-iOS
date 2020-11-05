//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kAES256_KeyByteLength;
extern const NSUInteger kAESGCM256_IVLength;
extern const NSUInteger kAES256CTR_IVLength;

extern const NSUInteger SCKErrorCodeFailedToDecryptMessage;

/// Key appropriate for use in AES256-GCM
@interface OWSAES256Key : NSObject <NSSecureCoding>

/// Generates new secure random key
- (instancetype)init;
+ (instancetype)generateRandomKey;

/**
 * @param data  representing the raw key bytes
 *
 * @returns a new instance if key is of appropriate length for AES256-GCM
 *          else returns nil.
 */
+ (nullable instancetype)keyWithData:(NSData *)data;

/// The raw key material
@property (nonatomic, readonly) NSData *keyData;

@end

#pragma mark -

// TODO: This class should probably be renamed to: AES256GCMEncryptionResult
// (note the missing 6 in 256).
@interface AES25GCMEncryptionResult : NSObject

@property (nonatomic, readonly) NSData *ciphertext;
@property (nonatomic, readonly) NSData *initializationVector;
@property (nonatomic, readonly) NSData *authTag;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithCipherText:(NSData *)cipherText
                       initializationVector:(NSData *)initializationVector
                                    authTag:(NSData *)authTag NS_DESIGNATED_INITIALIZER;

@end

#pragma mark -

@interface AES256CTREncryptionResult : NSObject

@property (nonatomic, readonly) NSData *ciphertext;
@property (nonatomic, readonly) NSData *initializationVector;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithCiphertext:(NSData *)ciphertext
                       initializationVector:(NSData *)initializationVector NS_DESIGNATED_INITIALIZER;

@end

#pragma mark -

@interface Cryptography : NSObject

typedef NS_ENUM(NSInteger, TSMACType) {
    TSHMACSHA256Truncated10Bytes = 2,
    TSHMACSHA256AttachementType  = 3
};

+ (NSData *)generateRandomBytes:(NSUInteger)numberBytes;

+ (uint32_t)randomUInt32;
+ (uint64_t)randomUInt64;
+ (unsigned)randomUnsigned;

#pragma mark - SHA and HMAC methods

// Full length SHA256 digest for `data`
+ (nullable NSData *)computeSHA256Digest:(NSData *)data;

// Truncated SHA256 digest for `data`
+ (nullable NSData *)computeSHA256Digest:(NSData *)data truncatedToBytes:(NSUInteger)truncatedBytes;

+ (nullable NSString *)truncatedSHA1Base64EncodedWithoutPadding:(NSString *)string;

+ (nullable NSData *)decryptAppleMessagePayload:(NSData *)payload withSignalingKey:(NSString *)signalingKeyString;

+ (nullable NSData *)computeSHA256HMAC:(NSData *)data withHMACKey:(NSData *)HMACKey;

+ (nullable NSData *)truncatedSHA256HMAC:(NSData *)dataToHMAC
                             withHMACKey:(NSData *)HMACKey
                              truncation:(NSUInteger)truncation;

#pragma mark - Attachments & Stickers

// Though digest can and will be nil for legacy clients, we now reject attachments lacking a digest.
+ (nullable NSData *)decryptAttachment:(NSData *)dataToDecrypt
                               withKey:(NSData *)key
                                digest:(nullable NSData *)digest
                          unpaddedSize:(UInt32)unpaddedSize
                                 error:(NSError **)error;

+ (nullable NSData *)decryptStickerData:(NSData *)dataToDecrypt
                                withKey:(NSData *)key
                                  error:(NSError **)error;

+ (nullable NSData *)encryptAttachmentData:(NSData *)attachmentData
                                    outKey:(NSData *_Nonnull *_Nullable)outKey
                                 outDigest:(NSData *_Nonnull *_Nullable)outDigest;

#pragma mark - AES-GCM

+ (nullable AES25GCMEncryptionResult *)encryptAESGCMWithData:(NSData *)plaintext
                                 additionalAuthenticatedData:(nullable NSData *)additionalAuthenticatedData
                                                         key:(OWSAES256Key *)key
    NS_SWIFT_NAME(encryptAESGCM(plainTextData:additionalAuthenticatedData:key:));

+ (nullable AES25GCMEncryptionResult *)encryptAESGCMWithData:(NSData *)plaintext
                                        initializationVector:(NSData *)initializationVector
                                 additionalAuthenticatedData:(nullable NSData *)additionalAuthenticatedData
                                                         key:(OWSAES256Key *)key
    NS_SWIFT_NAME(encryptAESGCM(plainTextData:initializationVector:additionalAuthenticatedData:key:));

+ (nullable NSData *)decryptAESGCMWithInitializationVector:(NSData *)initializationVector
                                                ciphertext:(NSData *)ciphertext
                               additionalAuthenticatedData:(nullable NSData *)additionalAuthenticatedData
                                                   authTag:(NSData *)authTagFromEncrypt
                                                       key:(OWSAES256Key *)key
    NS_SWIFT_NAME(decryptAESGCM(withInitializationVector:ciphertext:additionalAuthenticatedData:authTag:key:));

#pragma mark - Profiles

+ (nullable NSData *)encryptAESGCMWithProfileData:(NSData *)plaintextData key:(OWSAES256Key *)key
    NS_SWIFT_NAME(encryptAESGCMProfileData(plainTextData:key:));

+ (nullable NSData *)decryptAESGCMWithProfileData:(NSData *)encryptedData key:(OWSAES256Key *)key
    NS_SWIFT_NAME(decryptAESGCMProfileData(encryptedData:key:));

#pragma mark - AES-CTR

+ (nullable AES256CTREncryptionResult *)encryptAESCTRWithData:(NSData *)plaintext
                                         initializationVector:(NSData *)initializationVector
                                                          key:(OWSAES256Key *)key
    NS_SWIFT_NAME(encryptAESCTR(plaintextData:initializationVector:key:));

+ (nullable NSData *)decryptAESCTRWithCipherText:(NSData *)cipherText
                            initializationVector:(NSData *)initializationVector
                                             key:(OWSAES256Key *)key
    NS_SWIFT_NAME(decryptAESCTR(cipherText:initializationVector:key:));

#pragma mark -

+ (void)seedRandom;

@end

NS_ASSUME_NONNULL_END
