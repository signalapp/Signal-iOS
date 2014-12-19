//
//  FullImageViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface FullImageViewController : UIViewController

- (instancetype)initWithImage:(UIImage*)image fromRect:(CGRect)rect;

-(void)presentFromViewController:(UIViewController*)viewController;

@end
