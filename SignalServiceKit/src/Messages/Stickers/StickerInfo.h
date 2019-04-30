//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel+NSCoding.h>

NS_ASSUME_NONNULL_BEGIN

@class StickerPackInfo;

@interface StickerInfo : MTLModel

@property (nonatomic, readonly) NSData *packId;
@property (nonatomic, readonly) NSData *packKey;
@property (nonatomic, readonly) UInt32 stickerId;

- (instancetype)initWithPackId:(NSData *)packId packKey:(NSData *)packKey stickerId:(UInt32)stickerId;

- (NSString *)asKey;

@property (nonatomic, readonly) StickerPackInfo *packInfo;

@property (class, readonly, nonatomic) StickerInfo *defaultValue;

- (BOOL)isValid;

@end

#pragma mark -

@interface StickerPackInfo : MTLModel

@property (nonatomic, readonly) NSData *packId;
@property (nonatomic, readonly) NSData *packKey;

@property (class, readonly, nonatomic) StickerPackInfo *defaultValue;

- (instancetype)initWithPackId:(NSData *)packId packKey:(NSData *)packKey;

- (NSString *)asKey;

- (BOOL)isValid;

@end

NS_ASSUME_NONNULL_END
