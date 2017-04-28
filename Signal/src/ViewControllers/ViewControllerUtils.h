//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

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

+ (NSString *)formatFileSize:(unsigned long)fileSize;

#pragma mark - Alerts

+ (UIAlertController *)showAlertWithTitle:(NSString *)title message:(NSString *)message;

+ (UIAlertController *)showAlertWithTitle:(NSString *)title
                                  message:(NSString *)message
                              buttonLabel:(NSString *)buttonLabel;

+ (UIViewController *)topMostController;

@end
