//
//  FullImageViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TSAttachmentStream.h"
#import "TSInteraction.h"

@interface FullImageViewController : UIViewController

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment
                          fromRect:(CGRect)rect
                    forInteraction:(TSInteraction *)interaction
                        isAnimated:(BOOL)animated;

- (void)presentFromViewController:(UIViewController *)viewController;

@end
