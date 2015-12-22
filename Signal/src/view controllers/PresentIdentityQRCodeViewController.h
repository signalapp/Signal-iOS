//
//  PresentIdentityQRCodeViewController.h
//  Signal-iOS
//
//  Created by Christine Corbett Moran on 3/30/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface PresentIdentityQRCodeViewController : UIViewController
@property (nonatomic, strong) IBOutlet UIImageView *qrCodeView;
@property (nonatomic, strong) IBOutlet UILabel *yourFingerprintLabel;
@property (nonatomic, strong) NSData *identityKey;

@end
