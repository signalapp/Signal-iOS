//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "StickerUtils.h"
#import "OWSError.h"
#import <HKDFKit/HKDFKit.h>
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

@end

NS_ASSUME_NONNULL_END
