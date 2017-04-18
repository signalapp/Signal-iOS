//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import "TSAttachmentStream.h"

@interface FullscreenVideoViewController : UIViewController<UIViewControllerTransitioningDelegate>

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment
                          fromRect:(CGRect)rect;

- (void)presentFromViewController:(UIViewController *)viewController;

@end
