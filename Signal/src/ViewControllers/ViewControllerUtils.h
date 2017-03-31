//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ViewControllerUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;

// This convenience function can be used to reformat a phone number
// text field as the types, pastes, etc.
+ (void)phoneNumberTextField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
                      countryCode:(NSString *)countryCode;

@end
