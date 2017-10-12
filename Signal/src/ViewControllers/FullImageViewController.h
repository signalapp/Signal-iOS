//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class ConversationViewItem;
@class TSAttachmentStream;

@interface FullImageViewController : OWSViewController

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachmentStream
                          fromRect:(CGRect)rect
                          viewItem:(ConversationViewItem *)viewItem;

- (void)presentFromViewController:(UIViewController *)viewController;

@end

NS_ASSUME_NONNULL_END
