//
//  UIButton+OWS.m
//  Signal
//
//  Created by Christine Corbett Moran on 2/10/15.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "UIButton+OWS.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
@implementation UIButton (OWS)

+ (UIButton *)ows_blueButtonWithTitle:(NSString *)title {
    NSDictionary *buttonTextAttributes = @{
        NSFontAttributeName : [UIFont ows_regularFontWithSize:15.0f],
        NSForegroundColorAttributeName : [UIColor ows_materialBlueColor]
    };
    UIButton *button                           = [[UIButton alloc] init];
    NSMutableAttributedString *attributedTitle = [[NSMutableAttributedString alloc] initWithString:title];
    [attributedTitle setAttributes:buttonTextAttributes range:NSMakeRange(0, [attributedTitle length])];
    [button setAttributedTitle:attributedTitle forState:UIControlStateNormal];

    NSDictionary *disabledAttributes = @{
        NSFontAttributeName : [UIFont ows_regularFontWithSize:15.0f],
        NSForegroundColorAttributeName : [UIColor ows_darkGrayColor]
    };
    NSMutableAttributedString *attributedTitleDisabled = [[NSMutableAttributedString alloc] initWithString:title];
    [attributedTitleDisabled setAttributes:disabledAttributes range:NSMakeRange(0, [attributedTitle length])];
    [button setAttributedTitle:attributedTitleDisabled forState:UIControlStateDisabled];

    [button.titleLabel setTextAlignment:NSTextAlignmentCenter];

    return button;
}

@end
