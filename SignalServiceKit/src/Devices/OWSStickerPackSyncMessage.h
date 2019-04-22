//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, StickerPackOperationType) {
    StickerPackOperationType_Install,
    StickerPackOperationType_Remove,
};

#pragma mark -

@interface StickerPackInfo : NSObject

@property (nonatomic, readonly) NSData *packId;
@property (nonatomic, readonly) NSData *packKey;

- (instancetype)initWithPackId:(NSData *)packId packKey:(NSData *)packKey;

@end

#pragma mark -

@interface OWSStickerPackSyncMessage : OWSOutgoingSyncMessage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithPacks:(NSArray<StickerPackInfo *> *)packs operationType:(StickerPackOperationType)operationType;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
