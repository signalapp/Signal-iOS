//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "StickerUtils.h"
#import "OWSError.h"
#import <HKDFKit/HKDFKit.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation StickerUtils

+ (nullable NSData *)stickerKeyForPackKey:(NSData *)packKey
{
    @try {
        return [self throws_stickerKeyForPackKey:packKey];
    } @catch (NSException *exception) {
        OWSFailDebug(@"exception: %@ of type: %@ with reason: %@, user info: %@.",
                     exception.description,
                     exception.name,
                     exception.reason,
                     exception.userInfo);
        return nil;
    }
}

+ (nullable NSData *)throws_stickerKeyForPackKey:(NSData *)packKey
{
    if (packKey.length != StickerManager.packKeyLength) {
        OWSFailDebug(@"Pack Key must be 32 bytes");
        return nil;
    }
    
    NSData *infoData = [@"Sticker Pack" dataUsingEncoding:NSASCIIStringEncoding];
    NSData *nullSalt = [[NSMutableData dataWithLength:32] copy];
    NSData *stickerKey = [HKDFKit throws_deriveKey:packKey info:infoData salt:nullSalt outputSize:64];
    return stickerKey;
}

#define HMAC256_KEY_LENGTH 32
#define HMAC256_OUTPUT_LENGTH 32
#define AES_CBC_IV_LENGTH 16
#define AES_KEY_SIZE 32

+ (nullable NSData *)decryptAttachment:(NSData *)dataToDecrypt
                               withKey:(NSData *)key
                                 error:(NSError **)error
{
    NSData *_Nullable digest = nil;
//    if (digest.length <= 0) {
//        // This *could* happen with sufficiently outdated clients.
//        OWSLogError(@"Refusing to decrypt attachment without a digest.");
//        *error = OWSErrorWithCodeDescription(OWSErrorCodeInvalidStickerData,
//                                             NSLocalizedString(@"ERROR_MESSAGE_INVALID_MESSAGE", @""));
//        return nil;
//    }
    
    if (([dataToDecrypt length] < AES_CBC_IV_LENGTH + HMAC256_OUTPUT_LENGTH) ||
        ([key length] < AES_KEY_SIZE + HMAC256_KEY_LENGTH)) {
        OWSLogError(@"Message shorter than crypto overhead!");
        *error = OWSErrorWithCodeDescription(OWSErrorCodeInvalidStickerData,
                                             NSLocalizedString(@"ERROR_MESSAGE_INVALID_MESSAGE", @""));
        return nil;
    }
    
    // key: 32 byte AES key || 32 byte Hmac-SHA256 key.
    NSData *encryptionKey = [key subdataWithRange:NSMakeRange(0, AES_KEY_SIZE)];
    NSData *hmacKey       = [key subdataWithRange:NSMakeRange(AES_KEY_SIZE, HMAC256_KEY_LENGTH)];
    
    // dataToDecrypt: IV || Ciphertext || truncated MAC(IV||Ciphertext)
    NSData *iv                  = [dataToDecrypt subdataWithRange:NSMakeRange(0, AES_CBC_IV_LENGTH)];
    
    NSUInteger cipherTextLength;
    ows_sub_overflow(dataToDecrypt.length, (AES_CBC_IV_LENGTH + HMAC256_OUTPUT_LENGTH), &cipherTextLength);
    NSData *encryptedAttachment = [dataToDecrypt subdataWithRange:NSMakeRange(AES_CBC_IV_LENGTH, cipherTextLength)];
    
    NSUInteger hmacOffset;
    ows_sub_overflow(dataToDecrypt.length, HMAC256_OUTPUT_LENGTH, &hmacOffset);
    NSData *hmac = [dataToDecrypt subdataWithRange:NSMakeRange(hmacOffset, HMAC256_OUTPUT_LENGTH)];
    
    NSData *_Nullable paddedPlainText = [Cryptography decryptCBCMode:encryptedAttachment
                                                                 key:encryptionKey
                                                                  IV:iv
                                                             version:nil
                                                             HMACKey:hmacKey
                                                            HMACType:TSHMACSHA256AttachementType
                                                        matchingHMAC:hmac
                                                              digest:digest];
    if (!paddedPlainText) {
        OWSFailDebug(@"couldn't decrypt attachment.");
        *error = OWSErrorWithCodeDescription(OWSErrorCodeInvalidStickerData, NSLocalizedString(@"ERROR_MESSAGE_INVALID_MESSAGE", @""));
        return nil;
    } else {
        return paddedPlainText;
    }
}

@end

NS_ASSUME_NONNULL_END
