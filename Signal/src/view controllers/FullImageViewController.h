//
//  FullImageViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface FullImageViewController : UIViewController

@property(nonatomic, strong) IBOutlet UIImageView* fullImageView;
@property(nonatomic, strong) IBOutlet UIButton* saveButton;
@property(nonatomic, strong) IBOutlet UIButton* closeButton;

@property(nonatomic, strong) UIImage* image;


@end
