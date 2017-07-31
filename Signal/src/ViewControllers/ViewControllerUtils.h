//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ViewControllerUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;

// This convenience function can be used to reformat the contents of
// a phone number text field as the user modifies its text by typing,
// pasting, etc.
+ (void)phoneNumberTextField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
                      countryCode:(NSString *)countryCode;

+ (void)setAudioIgnoresHardwareMuteSwitch:(BOOL)shouldIgnore;

+ (NSString *)examplePhoneNumberForCountryCode:(NSString *)countryCode callingCode:(NSString *)callingCode;

#pragma mark - Formatting

+ (NSString *)formatInt:(int)value;

+ (NSString *)formatFileSize:(unsigned long)fileSize;

+ (NSString *)formatDurationSeconds:(long)timeSeconds;

@end

NS_ASSUME_NONNULL_END
