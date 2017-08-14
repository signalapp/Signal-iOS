//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kAES128_KeyByteLength;

/// Key appropriate for use in AES128 crypto
@interface OWSAES128Key: NSObject <NSSecureCoding>

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

+ (NSMutableData *)generateRandomBytes:(NSUInteger)numberBytes;

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
+ (NSData *)decryptAttachment:(NSData *)dataToDecrypt withKey:(NSData *)key digest:(nullable NSData *)digest;

+ (NSData *)encryptAttachmentData:(NSData *)attachmentData
                           outKey:(NSData *_Nonnull *_Nullable)outKey
                        outDigest:(NSData *_Nonnull *_Nullable)outDigest;

+ (nullable NSData *)encryptAESGCMWithData:(NSData *)plainTextData key:(OWSAES128Key *)key;
+ (nullable NSData *)decryptAESGCMWithData:(NSData *)encryptedData key:(OWSAES128Key *)key;

@end

NS_ASSUME_NONNULL_END
