//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class ConversationViewItem;
@class SignalAttachment;
@class TSAttachmentStream;

@interface MediaDetailViewController : OWSViewController

// If viewItem is non-null, long press will show a menu controller.
- (instancetype)initWithAttachmentStream:(TSAttachmentStream *)attachmentStream
                                fromRect:(CGRect)rect
                                viewItem:(ConversationViewItem *_Nullable)viewItem;

- (instancetype)initWithAttachment:(SignalAttachment *)attachment fromRect:(CGRect)rect;

- (void)presentFromViewController:(UIViewController *)viewController replacingView:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
