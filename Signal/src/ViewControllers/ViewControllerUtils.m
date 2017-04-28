//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ViewControllerUtils.h"
#import "Environment.h"
#import "PhoneNumber.h"
#import "SignalsViewController.h"
#import "StringUtil.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalServiceKit/PhoneNumberUtil.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@implementation ViewControllerUtils

+ (void)phoneNumberTextField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
                      countryCode:(NSString *)countryCode
{

    // Phone numbers takes many forms.
    //
    // * We only want to let the user enter decimal digits.
    // * The user shouldn't have to enter hyphen, parentheses or whitespace;
    //   the phone number should be formatted automatically.
    // * The user should be able to copy and paste freely.
    // * Invalid input should be simply ignored.
    //
    // We accomplish this by being permissive and trying to "take as much of the user
    // input as possible".
    //
    // * Always accept deletes.
    // * Ignore invalid input.
    // * Take partial input if possible.

    NSString *oldText = textField.text;
    // Construct the new contents of the text field by:
    // 1. Determining the "left" substring: the contents of the old text _before_ the deletion range.
    //    Filtering will remove non-decimal digit characters like hyphen "-".
    NSString *left = [oldText substringToIndex:range.location].digitsOnly;
    // 2. Determining the "right" substring: the contents of the old text _after_ the deletion range.
    NSString *right = [oldText substringFromIndex:range.location + range.length].digitsOnly;
    // 3. Determining the "center" substring: the contents of the new insertion text.
    NSString *center = insertionText.digitsOnly;
    // 4. Construct the "raw" new text by concatenating left, center and right.
    NSString *textAfterChange = [[left stringByAppendingString:center] stringByAppendingString:right];
    // 4a. Ensure we don't exceed the maximum length for a e164 phone number,
    //     15 digits, per: https://en.wikipedia.org/wiki/E.164
    const int kMaxPhoneNumberLength = 15;
    if (textAfterChange.length > kMaxPhoneNumberLength) {
        textAfterChange = [textAfterChange substringToIndex:kMaxPhoneNumberLength];
    }
    // 5. Construct the "formatted" new text by inserting a hyphen if necessary.
    // reformat the phone number, trying to keep the cursor beside the inserted or deleted digit
    bool isJustDeletion = insertionText.length == 0;
    NSUInteger cursorPositionAfterChange = MIN(left.length + center.length, textAfterChange.length);
    NSString *textAfterReformat =
        [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:textAfterChange
                                                     withSpecifiedCountryCodeString:countryCode];
    NSUInteger cursorPositionAfterReformat = [PhoneNumberUtil translateCursorPosition:cursorPositionAfterChange
                                                                                 from:textAfterChange
                                                                                   to:textAfterReformat
                                                                    stickingRightward:isJustDeletion];
    textField.text = textAfterReformat;
    UITextPosition *pos =
        [textField positionFromPosition:textField.beginningOfDocument offset:(NSInteger)cursorPositionAfterReformat];
    [textField setSelectedTextRange:[textField textRangeFromPosition:pos toPosition:pos]];
}

+ (void)setAudioIgnoresHardwareMuteSwitch:(BOOL)shouldIgnore
{
    NSError *error = nil;
    BOOL success = [[AVAudioSession sharedInstance]
        setCategory:(shouldIgnore ? AVAudioSessionCategoryPlayback : AVAudioSessionCategoryPlayAndRecord)error:&error];
    OWSAssert(!error);
    if (!success || error) {
        DDLogError(@"%@ Error in setAudioIgnoresHardwareMuteSwitch: %d", self.tag, shouldIgnore);
    }
}

+ (NSString *)formatFileSize:(unsigned long)fileSize
{
    const unsigned long kOneKilobyte = 1024;
    const unsigned long kOneMegabyte = kOneKilobyte * kOneKilobyte;

    NSNumberFormatter *numberFormatter = [NSNumberFormatter new];
    numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    return (fileSize > kOneMegabyte
            ? [[numberFormatter stringFromNumber:@(round(fileSize / (CGFloat)kOneMegabyte))]
                  stringByAppendingString:@" mb"]
            : (fileSize > kOneKilobyte
                      ? [[numberFormatter stringFromNumber:@(round(fileSize / (CGFloat)kOneKilobyte))]
                            stringByAppendingString:@" kb"]
                      : [[numberFormatter stringFromNumber:@(fileSize)] stringByAppendingString:@" bytes"]));
}

#pragma mark - Alerts

+ (UIAlertController *)showAlertWithTitle:(NSString *)title message:(NSString *)message
{
    return [self showAlertWithTitle:title message:message buttonLabel:NSLocalizedString(@"OK", nil)];
}

+ (UIAlertController *)showAlertWithTitle:(NSString *)title
                                  message:(NSString *)message
                              buttonLabel:(NSString *)buttonLabel
{
    OWSAssert(title.length > 0);
    OWSAssert(message.length > 0);

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:buttonLabel style:UIAlertActionStyleDefault handler:nil]];

    [self.topMostController presentViewController:alert animated:YES completion:nil];

    return alert;
}

+ (UIViewController *)topMostController
{
    UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;

    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }

    OWSAssert(topController);
    return topController;
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
