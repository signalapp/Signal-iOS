//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TappedStatusBarNotification;

@interface ViewControllerUtils : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// Performs cursory validation and change handling for phone number text field edits
// Allows UIKit to apply the majority of edits (unlike +phoneNumberTextField:changeCharacters...")
// which applies the edit manually.
// Useful when +phoneNumberTextField:changeCharactersInRange:... can't be used
// because it applies changes manually and requires failing any change request from UIKit.
+ (BOOL)phoneNumberTextField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
                      callingCode:(NSString *)callingCode;

// Reformats the text in a UITextField to apply phone number formatting
+ (void)reformatPhoneNumberTextField:(UITextField *)textField callingCode:(NSString *)callingCode;

// This convenience function can be used to reformat the contents of
// a phone number text field as the user modifies its text by typing,
// pasting, etc. Applies the incoming edit directly. The text field delegate
// should return NO from -textField:shouldChangeCharactersInRange:...
//
// "callingCode" should be of the form: "+1".
+ (void)phoneNumberTextField:(UITextField *)textField
     changeCharactersInRange:(NSRange)range
           replacementString:(NSString *)insertionText
                 callingCode:(NSString *)callingCode;

+ (void)ows2FAPINTextField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText;

+ (nullable NSString *)examplePhoneNumberForCountryCode:(NSString *)countryCode
                                            callingCode:(NSString *)callingCode
                                    includeExampleLabel:(BOOL)includeExampleLabel;

@end

NS_ASSUME_NONNULL_END
