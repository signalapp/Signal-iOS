//
//  FingerprintViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 02/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface FingerprintViewController : UIViewController

@property (nonatomic, strong) IBOutlet UILabel     * presentationLabel;

@property (nonatomic, strong) IBOutlet UIImageView * contactImageView;
@property (nonatomic, strong) IBOutlet UILabel     * contactFingerprintTitleLabel;
@property (nonatomic, strong) IBOutlet UILabel     * contactFingerprintLabel;

@property (nonatomic, strong) IBOutlet UIImageView * userImageView;
@property (nonatomic, strong) IBOutlet UILabel     * userFingerprintTitleLabel;
@property (nonatomic, strong) IBOutlet UILabel     * userFingerprintLabel;

@property (nonatomic, strong) IBOutlet UIButton    * closeButton;
@property (nonatomic, strong) IBOutlet UIButton    * shredMessagesAndContactButton;

@end
