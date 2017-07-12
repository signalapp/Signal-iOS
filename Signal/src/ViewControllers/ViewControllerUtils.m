//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ViewControllerUtils.h"
#import "Environment.h"
#import "PhoneNumber.h"
#import "Signal-Swift.h"
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
    //
    // NOTE: The actual limit is 18, not 15, because of certain invalid phone numbers in Germany.
    //       https://github.com/googlei18n/libphonenumber/blob/master/FALSEHOODS.md
    const int kMaxPhoneNumberLength = 18;
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

+ (NSString *)examplePhoneNumberForCountryCode:(NSString *)countryCode callingCode:(NSString *)callingCode
{
    OWSAssert(countryCode.length > 0);
    OWSAssert(callingCode.length > 0);

    NSString *examplePhoneNumber = [PhoneNumberUtil examplePhoneNumberForCountryCode:countryCode];
    OWSAssert(!examplePhoneNumber || [examplePhoneNumber hasPrefix:callingCode]);
    if (examplePhoneNumber && [examplePhoneNumber hasPrefix:callingCode]) {
        NSString *formattedPhoneNumber =
            [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:examplePhoneNumber
                                                         withSpecifiedCountryCodeString:countryCode];
        if (formattedPhoneNumber.length > 0) {
            examplePhoneNumber = formattedPhoneNumber;
        }

        return [NSString
            stringWithFormat:
                NSLocalizedString(@"PHONE_NUMBER_EXAMPLE_FORMAT",
                    @"A format for a label showing an example phone number. Embeds {{the example phone number}}."),
            [examplePhoneNumber substringFromIndex:callingCode.length]];
    } else {
        return @"";
    }
}

#pragma mark - Formatting

+ (NSString *)formatInt:(int)value
{
    static NSNumberFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSNumberFormatter new];
        formatter.numberStyle = NSNumberFormatterNoStyle;
    });
    return [formatter stringFromNumber:@(value)];
}

+ (NSString *)formatFileSize:(unsigned long)fileSize
{
    const unsigned long kOneKilobyte = 1024;
    const unsigned long kOneMegabyte = kOneKilobyte * kOneKilobyte;

    NSNumberFormatter *numberFormatter = [NSNumberFormatter new];
    numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;

    if (fileSize > kOneMegabyte * 10) {
        return [[numberFormatter stringFromNumber:@((int)round(fileSize / (CGFloat)kOneMegabyte))]
            stringByAppendingString:@" MB"];
    } else if (fileSize > kOneKilobyte * 10) {
        return [[numberFormatter stringFromNumber:@((int)round(fileSize / (CGFloat)kOneKilobyte))]
            stringByAppendingString:@" KB"];
    } else {
        return [NSString stringWithFormat:@"%lu Bytes", fileSize];
    }
}

+ (NSString *)formatDurationSeconds:(long)timeSeconds
{
    long seconds = timeSeconds % 60;
    long minutes = (timeSeconds / 60) % 60;
    long hours = timeSeconds / 3600;

    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", hours, minutes, seconds];
    } else {
        return [NSString stringWithFormat:@"%ld:%02ld", minutes, seconds];
    }
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
