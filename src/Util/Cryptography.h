//
//  Cryptography.h
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 3/26/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSAttachmentEncryptionResult.h"

@interface Cryptography : NSObject

typedef NS_ENUM(NSInteger, TSMACType) {
    TSHMACSHA1Truncated10Bytes   = 1,
    TSHMACSHA256Truncated10Bytes = 2,
    TSHMACSHA256AttachementType  = 3
};

+ (NSMutableData *)generateRandomBytes:(NSUInteger)numberBytes;

#pragma mark SHA and HMAC methods

+ (NSData *)computeSHA256:(NSData *)data truncatedToBytes:(NSUInteger)truncatedBytes;
+ (NSString *)truncatedSHA1Base64EncodedWithoutPadding:(NSString *)string;
+ (NSString *)computeSHA1DigestForString:(NSString *)input;

+ (NSData *)computeSHA256HMAC:(NSData *)dataToHMAC withHMACKey:(NSData *)HMACKey;
+ (NSData *)computeSHA1HMAC:(NSData *)dataToHMAC withHMACKey:(NSData *)HMACKey;
+ (NSData *)truncatedSHA1HMAC:(NSData *)dataToHMAC withHMACKey:(NSData *)HMACKey truncation:(NSUInteger)bytes;

+ (NSData *)decryptAppleMessagePayload:(NSData *)payload withSignalingKey:(NSString *)signalingKeyString;

#pragma mark encrypt and decrypt attachment data
+ (NSData *)decryptAttachment:(NSData *)dataToDecrypt withKey:(NSData *)key;

+ (TSAttachmentEncryptionResult *)encryptAttachment:(NSData *)attachment
                                        contentType:(NSString *)contentType
                                         identifier:(NSString *)identifier;
@end
