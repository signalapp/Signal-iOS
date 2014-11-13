//
//  RegistrationViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface RegistrationViewController : UIViewController

// Country code
@property(nonatomic, strong) IBOutlet UIButton* countryCodeButton;
@property(nonatomic, strong) IBOutlet UILabel* countryNameLabel;
@property(nonatomic, strong) IBOutlet UILabel* countryCodeLabel;

//Phone number
@property(nonatomic, strong) IBOutlet UITextField* phoneNumberTextField;



@end
