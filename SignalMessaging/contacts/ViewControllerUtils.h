//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern const NSUInteger kMin2FAPinLength;
extern const NSUInteger kMax2FAPinLength;
extern NSString *const TappedStatusBarNotification;

@interface ViewControllerUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;

// This convenience function can be used to reformat the contents of
// a phone number text field as the user modifies its text by typing,
// pasting, etc.
+ (void)phoneNumberTextField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
                      countryCode:(NSString *)countryCode;

+ (void)ows2FAPINTextField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText;

+ (NSString *)examplePhoneNumberForCountryCode:(NSString *)countryCode callingCode:(NSString *)callingCode;

@end

NS_ASSUME_NONNULL_END
