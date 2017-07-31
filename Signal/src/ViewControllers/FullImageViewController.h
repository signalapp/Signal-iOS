//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageData.h"
#import "OWSViewController.h"
#import "TSAttachmentStream.h"
#import "TSInteraction.h"
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FullImageViewController : OWSViewController

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment
                          fromRect:(CGRect)rect
                    forInteraction:(TSInteraction *)interaction
                       messageItem:(id<OWSMessageData>)messageItem
                        isAnimated:(BOOL)animated;

- (void)presentFromViewController:(UIViewController *)viewController;

@end

NS_ASSUME_NONNULL_END
