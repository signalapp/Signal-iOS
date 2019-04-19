//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel+NSCoding.h>

NS_ASSUME_NONNULL_BEGIN

@interface StickerInfo : MTLModel

@property (nonatomic, readonly) NSData *packId;
@property (nonatomic, readonly) NSData *packKey;
@property (nonatomic, readonly) UInt32 stickerId;

- (instancetype)initWithPackId:(NSData *)packId packKey:(NSData *)packKey stickerId:(UInt32)stickerId;

- (NSString *)asKey;

@property (class, readonly, nonatomic) StickerInfo *defaultValue;

@end

#pragma mark -

@interface StickerPackInfo : MTLModel

@property (nonatomic, readonly) NSData *packId;
@property (nonatomic, readonly) NSData *packKey;

- (instancetype)initWithPackId:(NSData *)packId packKey:(NSData *)packKey;

- (NSString *)asKey;

@end

NS_ASSUME_NONNULL_END
