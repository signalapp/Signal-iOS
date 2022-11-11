//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

+ (nullable StickerPackInfo *)parsePackIdHex:(nullable NSString *)packIdHex packKeyHex:(nullable NSString *)packKeyHex
{
    if (packIdHex == nil || packIdHex.length < 1) {
        OWSLogDebug(@"Invalid packIdHex: %@", packIdHex);
        OWSFailDebug(@"Invalid packIdHex.");
        return nil;
    }
    if (packKeyHex == nil || packKeyHex.length < 1) {
        OWSLogDebug(@"Invalid packKeyHex: %@", packKeyHex);
        OWSFailDebug(@"Invalid packKeyHex.");
        return nil;
    }
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

- (NSString *)shareUrl
{
    return [NSString stringWithFormat:@"https://signal.art/addstickers/#pack_id=%@&pack_key=%@",
                     self.packId.hexadecimalString,
                     self.packKey.hexadecimalString];
}

+ (BOOL)isStickerPackShareUrl:(NSURL *)url
{
    return ([url.scheme isEqualToString:@"https"] && (url.user == NULL) && (url.password == NULL) &&
        [url.host isEqualToString:@"signal.art"] && (url.port == NULL) && [url.path isEqualToString:@"/addstickers"]);
}

+ (nullable StickerPackInfo *)parseStickerPackShareUrl:(NSURL *)url
{
    if (![self isStickerPackShareUrl:url]) {
        OWSFailDebug(@"Invalid URL.");
        return nil;
    }

    NSString *_Nullable packIdHex;
    NSString *_Nullable packKeyHex;
    NSURLComponents *components = [NSURLComponents componentsWithString:url.absoluteString];
    NSString *_Nullable fragment = components.fragment;
    for (NSString *fragmentSegment in [fragment componentsSeparatedByString:@"&"]) {
        NSArray<NSString *> *fragmentSlices = [fragmentSegment componentsSeparatedByString:@"="];
        if (fragmentSlices.count != 2) {
            OWSFailDebug(@"Invalid fragment: %@", fragment);
            continue;
        }
        NSString *fragmentName = fragmentSlices[0];
        NSString *fragmentValue = fragmentSlices[1];
        if ([fragmentName isEqualToString:@"pack_id"]) {
            OWSAssertDebug(packIdHex == nil);
            packIdHex = fragmentValue;
        } else if ([fragmentName isEqualToString:@"pack_key"]) {
            OWSAssertDebug(packKeyHex == nil);
            packKeyHex = fragmentValue;
        } else {
            OWSLogWarn(@"Unknown query item: %@", fragmentName);
        }
    }

    return [StickerPackInfo parsePackIdHex:packIdHex packKeyHex:packKeyHex];
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
