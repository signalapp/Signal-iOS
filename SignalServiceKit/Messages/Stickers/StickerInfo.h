//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@class StickerPackInfo;

@interface StickerInfo : NSObject <NSCoding, NSCopying>

@property (nonatomic, readonly) NSData *packId;
@property (nonatomic, readonly) NSData *packKey;
@property (nonatomic, readonly) UInt32 stickerId;

- (instancetype)initWithPackId:(NSData *)packId packKey:(NSData *)packKey stickerId:(UInt32)stickerId;

- (NSString *)asKey;
+ (NSString *)keyWithPackId:(NSData *)packId stickerId:(UInt32)stickerId;

@property (nonatomic, readonly) StickerPackInfo *packInfo;

@property (class, readonly, nonatomic) StickerInfo *defaultValue;

- (BOOL)isValid;

@end

NS_ASSUME_NONNULL_END
