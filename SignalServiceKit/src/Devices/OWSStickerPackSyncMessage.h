//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"
#import "StickerInfo.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, StickerPackOperationType) {
    StickerPackOperationType_Install,
    StickerPackOperationType_Remove,
};

@interface OWSStickerPackSyncMessage : OWSOutgoingSyncMessage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithPacks:(NSArray<StickerPackInfo *> *)packs operationType:(StickerPackOperationType)operationType;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
