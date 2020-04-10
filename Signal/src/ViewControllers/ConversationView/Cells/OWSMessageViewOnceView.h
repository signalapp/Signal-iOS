//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageView.h"

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

@protocol OWSMessageViewOnceViewDelegate

- (void)didTapViewOnceAttachment:(id<ConversationViewItem>)viewItem
                attachmentStream:(TSAttachmentStream *)attachmentStream;

- (void)didTapViewOnceExpired:(id<ConversationViewItem>)viewItem;

- (void)didTapFailedIncomingAttachment:(id<ConversationViewItem>)viewItem;

@end

#pragma mark -

@interface OWSMessageViewOnceView : OWSMessageView

@property (nonatomic, weak) id<OWSMessageViewOnceViewDelegate> delegate;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
