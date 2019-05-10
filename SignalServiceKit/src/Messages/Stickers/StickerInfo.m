//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "StickerInfo.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation StickerInfo

- (instancetype)initWithPackId:(NSData *)packId packKey:(NSData *)packKey stickerId:(UInt32)stickerId
{
    self = [super init];

    if (!self) {
        return self;
    }

    _packId = packId;
    _packKey = packKey;
    _stickerId = stickerId;

    OWSAssertDebug(self.isValid);

    return self;
}

- (NSString *)asKey
{
    return [NSString stringWithFormat:@"%@.%lu", self.packId.hexadecimalString, (unsigned long)self.stickerId];
}

+ (StickerInfo *)defaultValue
{
    return [[StickerInfo alloc] initWithPackId:[Randomness generateRandomBytes:16]
                                       packKey:[Randomness generateRandomBytes:(int)StickerManager.packKeyLength]
                                     stickerId:0];
}

- (StickerPackInfo *)packInfo
{
    return [[StickerPackInfo alloc] initWithPackId:self.packId packKey:self.packKey];
}

- (BOOL)isValid
{
    return (self.packId.length > 0 && self.packKey.length == StickerManager.packKeyLength);
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@, %d", self.packId.hexadecimalString, (int)self.stickerId];
}

@end

#pragma mark -

@implementation StickerPackInfo

- (instancetype)initWithPackId:(NSData *)packId packKey:(NSData *)packKey
{
    self = [super init];

    if (!self) {
        return self;
    }

    _packId = packId;
    _packKey = packKey;

    OWSAssertDebug(self.isValid);

    return self;
}

+ (nullable StickerPackInfo *)parsePackIdHex:(NSString *)packIdHex packKeyHex:(NSString *)packKeyHex
{
    NSData *_Nullable packId = [NSData dataFromHexString:packIdHex];
    NSData *_Nullable packKey = [NSData dataFromHexString:packKeyHex];
    return [self parsePackId:packId packKey:packKey];
}

+ (nullable StickerPackInfo *)parsePackId:(nullable NSData *)packId packKey:(nullable NSData *)packKey
{
    if (packId == nil || packId.length < 1) {
        OWSLogDebug(@"Invalid packId: %@", packId);
        OWSFailDebug(@"Invalid packId.");
        return nil;
    }
    if (packKey == nil || packKey.length != StickerManager.packKeyLength) {
        OWSLogDebug(@"Invalid packKey: %@", packKey);
        OWSFailDebug(@"Invalid packKey.");
        return nil;
    }
    return [[StickerPackInfo alloc] initWithPackId:packId packKey:packKey];
}

- (NSString *)asKey
{
    return self.packId.hexadecimalString;
}

- (BOOL)isValid
{
    return (self.packId.length > 0 && self.packKey.length == StickerManager.packKeyLength);
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@", self.packId.hexadecimalString];
}

@end

NS_ASSUME_NONNULL_END
