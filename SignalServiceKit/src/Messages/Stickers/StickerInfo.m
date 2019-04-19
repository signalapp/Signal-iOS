//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "StickerInfo.h"
#import <SignalCoreKit/NSData+OWS.h>

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

    return self;
}

- (NSString *)asKey
{
    return [NSString stringWithFormat:@"%@.%lu", self.packId.hexadecimalString, (unsigned long)self.stickerId];
}

+ (StickerInfo *)defaultValue
{
    return [[StickerInfo alloc] initWithPackId:[NSData new] packKey:[NSData new] stickerId:0];
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

    return self;
}

- (NSString *)asKey
{
    return self.packId.hexadecimalString;
}

@end

NS_ASSUME_NONNULL_END
