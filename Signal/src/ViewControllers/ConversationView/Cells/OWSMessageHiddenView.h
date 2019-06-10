//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageView.h"

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

@protocol OWSMessageHiddenViewDelegate

- (void)didTapAttachmentWithPerMessageExpiration:(id<ConversationViewItem>)viewItem
                                attachmentStream:(TSAttachmentStream *)attachmentStream;

- (void)didTapFailedIncomingAttachment:(id<ConversationViewItem>)viewItem;

@end

#pragma mark -

@interface OWSMessageHiddenView : OWSMessageView

@property (nonatomic, weak) id<OWSMessageHiddenViewDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithFrame:(CGRect)frame NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
