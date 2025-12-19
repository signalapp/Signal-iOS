//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "StickerPack.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation StickerPackItem

- (instancetype)initWithStickerId:(UInt32)stickerId
                      emojiString:(NSString *)emojiString
                      contentType:(nullable NSString *)contentType
{
    self = [super init];

    if (!self) {
        return self;
    }

    _stickerId = stickerId;
    _emojiString = emojiString;
    if (contentType.length > 0) {
        _contentType = contentType;
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    NSString *contentType = self.contentType;
    if (contentType != nil) {
        [coder encodeObject:contentType forKey:@"contentType"];
    }
    NSString *emojiString = self.emojiString;
    if (emojiString != nil) {
        [coder encodeObject:emojiString forKey:@"emojiString"];
    }
    [coder encodeObject:[self valueForKey:@"stickerId"] forKey:@"stickerId"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (!self) {
        return self;
    }
    self->_contentType = [coder decodeObjectOfClass:[NSString class] forKey:@"contentType"];
    self->_emojiString = [coder decodeObjectOfClass:[NSString class] forKey:@"emojiString"];
    self->_stickerId = [(NSNumber *)[coder decodeObjectOfClass:[NSNumber class] forKey:@"stickerId"] unsignedIntValue];
    return self;
}

- (NSUInteger)hash
{
    NSUInteger result = 0;
    result ^= self.contentType.hash;
    result ^= self.emojiString.hash;
    result ^= self.stickerId;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![other isMemberOfClass:self.class]) {
        return NO;
    }
    StickerPackItem *typedOther = (StickerPackItem *)other;
    if (![NSObject isObject:self.contentType equalToObject:typedOther.contentType]) {
        return NO;
    }
    if (![NSObject isObject:self.emojiString equalToObject:typedOther.emojiString]) {
        return NO;
    }
    if (self.stickerId != typedOther.stickerId) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    StickerPackItem *result = [[[self class] allocWithZone:zone] init];
    result->_contentType = self.contentType;
    result->_emojiString = self.emojiString;
    result->_stickerId = self.stickerId;
    return result;
}

- (StickerInfo *)stickerInfoWithStickerPack:(StickerPack *)stickerPack
{
    return [[StickerInfo alloc] initWithPackId:stickerPack.packId packKey:stickerPack.packKey stickerId:self.stickerId];
}

@end

#pragma mark -

@interface StickerPack ()

@property (nonatomic) BOOL isInstalled;

@end

#pragma mark -

@implementation StickerPack

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.author.hash;
    result ^= self.cover.hash;
    result ^= self.dateCreated.hash;
    result ^= self.info.hash;
    result ^= self.isInstalled;
    result ^= self.items.hash;
    result ^= self.title.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    StickerPack *typedOther = (StickerPack *)other;
    if (![NSObject isObject:self.author equalToObject:typedOther.author]) {
        return NO;
    }
    if (![NSObject isObject:self.cover equalToObject:typedOther.cover]) {
        return NO;
    }
    if (![NSObject isObject:self.dateCreated equalToObject:typedOther.dateCreated]) {
        return NO;
    }
    if (![NSObject isObject:self.info equalToObject:typedOther.info]) {
        return NO;
    }
    if (self.isInstalled != typedOther.isInstalled) {
        return NO;
    }
    if (![NSObject isObject:self.items equalToObject:typedOther.items]) {
        return NO;
    }
    if (![NSObject isObject:self.title equalToObject:typedOther.title]) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    StickerPack *result = [self copyAndAssignIdsWithZone:zone];
    result->_author = self.author;
    result->_cover = self.cover;
    result->_dateCreated = self.dateCreated;
    result->_info = self.info;
    result->_isInstalled = self.isInstalled;
    result->_items = self.items;
    result->_title = self.title;
    return result;
}

- (instancetype)initWithInfo:(StickerPackInfo *)info
                       title:(nullable NSString *)title
                      author:(nullable NSString *)author
                       cover:(StickerPackItem *)cover
                    stickers:(NSArray<StickerPackItem *> *)items
{
    OWSAssertDebug(info.packId.length > 0);
    OWSAssertDebug(info.packKey.length > 0);
    // Title and empty might be nil or empty.
    OWSAssertDebug(cover);
    OWSAssertDebug(items.count > 0);

    self = [super initWithUniqueId:[StickerPack uniqueIdForStickerPackInfo:info]];

    if (!self) {
        return self;
    }

    _info = info;
    _title = title;
    _author = author;
    _cover = cover;
    _items = items;
    _dateCreated = [NSDate new];

    return self;
}

- (NSData *)packId
{
    return self.info.packId;
}

- (NSData *)packKey
{
    return self.info.packKey;
}

- (StickerInfo *)coverInfo
{
    return [[StickerInfo alloc] initWithPackId:self.packId packKey:self.packKey stickerId:self.cover.stickerId];
}

- (NSArray<StickerInfo *> *)stickerInfos
{
    NSMutableArray<StickerInfo *> *stickerInfos = [NSMutableArray new];
    for (StickerPackItem *item in self.items) {
        [stickerInfos addObject:[item stickerInfoWithStickerPack:self]];
    }
    return stickerInfos;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run
// `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
                          author:(nullable NSString *)author
                           cover:(StickerPackItem *)cover
                     dateCreated:(NSDate *)dateCreated
                            info:(StickerPackInfo *)info
                     isInstalled:(BOOL)isInstalled
                           items:(NSArray<StickerPackItem *> *)items
                           title:(nullable NSString *)title
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _author = author;
    _cover = cover;
    _dateCreated = dateCreated;
    _info = info;
    _isInstalled = isInstalled;
    _items = items;
    _title = title;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

+ (NSString *)uniqueIdForStickerPackInfo:(StickerPackInfo *)info
{
    return info.asKey;
}

- (void)updateWithIsInstalled:(BOOL)isInstalled transaction:(DBWriteTransaction *)transaction
{
    [self anyUpdateWithTransaction:transaction block:^(StickerPack *instance) { instance.isInstalled = isInstalled; }];
}

@end

NS_ASSUME_NONNULL_END
