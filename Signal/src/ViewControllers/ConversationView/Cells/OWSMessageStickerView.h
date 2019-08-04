//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageView.h"

NS_ASSUME_NONNULL_BEGIN

@class StickerPackInfo;

@protocol OWSMessageStickerViewDelegate

- (void)showStickerPack:(StickerPackInfo *)stickerPackInfo;

@end

#pragma mark -

@interface OWSMessageStickerView : OWSMessageView

@property (nonatomic, weak) id<OWSMessageStickerViewDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
