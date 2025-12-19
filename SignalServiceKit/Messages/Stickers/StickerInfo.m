//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "StickerInfo.h"
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

- (void)encodeWithCoder:(NSCoder *)coder
{
    NSData *packId = self.packId;
    if (packId != nil) {
        [coder encodeObject:packId forKey:@"packId"];
    }
    NSData *packKey = self.packKey;
    if (packKey != nil) {
        [coder encodeObject:packKey forKey:@"packKey"];
    }
    [coder encodeObject:[self valueForKey:@"stickerId"] forKey:@"stickerId"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_packId = [coder decodeObjectOfClass:[NSData class] forKey:@"packId"];
    self->_packKey = [coder decodeObjectOfClass:[NSData class] forKey:@"packKey"];
    self->_stickerId = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:@"stickerId"] unsignedIntValue];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.packId.hash;
    result ^= self.packKey.hash;
    result ^= self.stickerId;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    StickerInfo *typedOther = (StickerInfo *)other;
    if (![NSObject isObject:self.packId equalToObject:typedOther.packId]) {
        return NO;
    }
    if (![NSObject isObject:self.packKey equalToObject:typedOther.packKey]) {
        return NO;
    }
    if (self.stickerId != typedOther.stickerId) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    StickerInfo *result = [[[self class] allocWithZone:zone] init];
    result->_packId = self.packId;
    result->_packKey = self.packKey;
    result->_stickerId = self.stickerId;
    return result;
}

- (NSString *)asKey
{
    return [StickerInfo keyWithPackId:self.packId stickerId:self.stickerId];
}

+ (NSString *)keyWithPackId:(NSData *)packId stickerId:(UInt32)stickerId
{
    return [NSString stringWithFormat:@"%@.%lu", packId.hexadecimalString, (unsigned long)stickerId];
}

+ (StickerInfo *)defaultValue
{
    return [[StickerInfo alloc] initWithPackId:[Randomness generateRandomBytes:16]
                                       packKey:[Randomness generateRandomBytes:StickerManager.packKeyLength]
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

NS_ASSUME_NONNULL_END
