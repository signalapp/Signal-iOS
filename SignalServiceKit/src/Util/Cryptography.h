//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kAES256_KeyByteLength;

/// Key appropriate for use in AES128 crypto
@interface OWSAES256Key : NSObject <NSSecureCoding>

/// Generates new secure random key
- (instancetype)init;
+ (instancetype)generateRandomKey;

/**
 * @param data  representing the raw key bytes
 *
 * @returns a new instance if key is of appropriate length for AES128 crypto
 *          else returns nil.
 */
+ (nullable instancetype)keyWithData:(NSData *)data;

/// The raw key material
@property (nonatomic, readonly) NSData *keyData;

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

#pragma mark - SHA and HMAC methods

// Full length SHA256 digest for `data`
+ (nullable NSData *)computeSHA256Digest:(NSData *)data;

// Truncated SHA256 digest for `data`
+ (nullable NSData *)computeSHA256Digest:(NSData *)data truncatedToBytes:(NSUInteger)truncatedBytes;

+ (nullable NSString *)truncatedSHA1Base64EncodedWithoutPadding:(NSString *)string;

+ (nullable NSData *)decryptAppleMessagePayload:(NSData *)payload withSignalingKey:(NSString *)signalingKeyString;

#pragma mark encrypt and decrypt attachment data

// Though digest can and will be nil for legacy clients, we now reject attachments lacking a digest.
+ (nullable NSData *)decryptAttachment:(NSData *)dataToDecrypt
                               withKey:(NSData *)key
                                digest:(nullable NSData *)digest
                          unpaddedSize:(UInt32)unpaddedSize
                                 error:(NSError **)error;

+ (nullable NSData *)encryptAttachmentData:(NSData *)attachmentData
                                    outKey:(NSData *_Nonnull *_Nullable)outKey
                                 outDigest:(NSData *_Nonnull *_Nullable)outDigest;

+ (nullable NSData *)encryptAESGCMWithData:(NSData *)plaintextData key:(OWSAES256Key *)key;
+ (nullable NSData *)decryptAESGCMWithData:(NSData *)encryptedData key:(OWSAES256Key *)key;

@end

NS_ASSUME_NONNULL_END
