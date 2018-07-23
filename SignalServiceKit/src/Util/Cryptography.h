//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kAES256_KeyByteLength;

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

@interface AES25GCMEncryptionResult : NSObject

@property (nonatomic, readonly) NSData *ciphertext;
@property (nonatomic, readonly) NSData *initializationVector;
@property (nonatomic, readonly) NSData *authTag;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithCipherText:(NSData *)cipherText
                       initializationVector:(NSData *)initializationVector
                                    authTag:(NSData *)authTag NS_DESIGNATED_INITIALIZER;

@end

@interface Cryptography : NSObject

typedef NS_ENUM(NSInteger, TSMACType) {
    TSHMACSHA1Truncated10Bytes   = 1,
    TSHMACSHA256Truncated10Bytes = 2,
    TSHMACSHA256AttachementType  = 3
};

+ (NSData *)generateRandomBytes:(NSUInteger)numberBytes;

+ (uint32_t)randomUInt32;
+ (uint64_t)randomUInt64;

#pragma mark SHA and HMAC methods

// Full length SHA256 digest for `data`
+ (NSData *)computeSHA256Digest:(NSData *)data;

// Truncated SHA256 digest for `data`
+ (NSData *)computeSHA256Digest:(NSData *)data truncatedToBytes:(NSUInteger)truncatedBytes;

+ (NSString *)truncatedSHA1Base64EncodedWithoutPadding:(NSString *)string;
+ (NSString *)computeSHA1DigestForString:(NSString *)input;

+ (NSData *)computeSHA256HMAC:(NSData *)dataToHMAC withHMACKey:(NSData *)HMACKey;
+ (NSData *)computeSHA1HMAC:(NSData *)dataToHMAC withHMACKey:(NSData *)HMACKey;
+ (NSData *)truncatedSHA1HMAC:(NSData *)dataToHMAC withHMACKey:(NSData *)HMACKey truncation:(NSUInteger)bytes;

+ (NSData *)decryptAppleMessagePayload:(NSData *)payload withSignalingKey:(NSString *)signalingKeyString;

#pragma mark encrypt and decrypt attachment data

// Though digest can and will be nil for legacy clients, we now reject attachments lacking a digest.
+ (NSData *)decryptAttachment:(NSData *)dataToDecrypt
                      withKey:(NSData *)key
                       digest:(nullable NSData *)digest
                 unpaddedSize:(UInt32)unpaddedSize
                        error:(NSError **)error;

+ (NSData *)encryptAttachmentData:(NSData *)attachmentData
                           outKey:(NSData *_Nonnull *_Nullable)outKey
                        outDigest:(NSData *_Nonnull *_Nullable)outDigest;

+ (nullable AES25GCMEncryptionResult *)encryptAESGCMWithData:(NSData *)plaintext
                                 additionalAuthenticatedData:(nullable NSData *)additionalAuthenticatedData
                                                         key:(OWSAES256Key *)key
  NS_SWIFT_NAME(encryptAESGCM(plainTextData:additionalAuthenticatedData:key:));

+ (nullable NSData *)decryptAESGCMWithInitializationVector:(NSData *)initializationVector
                                                ciphertext:(NSData *)ciphertext
                               additionalAuthenticatedData:(nullable NSData *)additionalAuthenticatedData
                                                   authTag:(NSData *)authTagFromEncrypt
                                                       key:(OWSAES256Key *)key;

+ (nullable NSData *)encryptAESGCMWithProfileData:(NSData *)plaintextData key:(OWSAES256Key *)key;
+ (nullable NSData *)decryptAESGCMWithProfileData:(NSData *)encryptedData key:(OWSAES256Key *)key;

@end

NS_ASSUME_NONNULL_END
