//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageView.h"

NS_ASSUME_NONNULL_BEGIN

@protocol OWSMessageStickerViewDelegate

@end

#pragma mark -

@interface OWSMessageStickerView : OWSMessageView

@property (nonatomic, weak) id<OWSMessageStickerViewDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

#pragma mark - Gestures

// This only needs to be called when we use the cell _outside_ the context
// of a conversation view message cell.
- (void)addTapGestureHandler;

@end

NS_ASSUME_NONNULL_END
