//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class ConversationViewItem;
@class SignalAttachment;
@class TSAttachmentStream;

@interface MediaDetailViewController : OWSViewController

// If viewItem is non-null, long press will show a menu controller.
- (instancetype)initWithAttachmentStream:(TSAttachmentStream *)attachmentStream
                                viewItem:(ConversationViewItem *_Nullable)viewItem;

- (instancetype)initWithAttachment:(SignalAttachment *)attachment;

- (void)presentFromViewController:(UIViewController *)viewController replacingView:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
