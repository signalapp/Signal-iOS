//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ViewControllerUtils.h"
#import "NSString+OWS.h"
#import "PhoneNumber.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/PhoneNumberUtil.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TappedStatusBarNotification = @"TappedStatusBarNotification";

const NSUInteger kMin2FAPinLength = 4;
const NSUInteger kMax2FAPinLength = 16;

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

    // 3a. If user hits backspace, they should always delete a _digit_ to the
    //     left of the cursor, even if the text _immediately_ to the left of
    //     cursor is "formatting text" (e.g. whitespace, a hyphen or a
    //     parentheses).
    bool isJustDeletion = insertionText.length == 0;
    if (isJustDeletion) {
        NSString *deletedText = [oldText substringWithRange:range];
        BOOL didDeleteFormatting = (deletedText.length == 1 && deletedText.digitsOnly.length < 1);
        if (didDeleteFormatting && left.length > 0) {
            left = [left substringToIndex:left.length - 1];
        }
    }

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

+ (void)ows2FAPINTextField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
{
    // * We only want to let the user enter decimal digits.
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
    //    Filtering will remove non-decimal digit characters.
    NSString *left = [oldText substringToIndex:range.location].digitsOnly;
    // 2. Determining the "right" substring: the contents of the old text _after_ the deletion range.
    NSString *right = [oldText substringFromIndex:range.location + range.length].digitsOnly;
    // 3. Determining the "center" substring: the contents of the new insertion text.
    NSString *center = insertionText.digitsOnly;
    // 4. Construct the "raw" new text by concatenating left, center and right.
    NSString *textAfterChange = [[left stringByAppendingString:center] stringByAppendingString:right];
    // 5. Ensure we don't exceed the maximum length for a PIN.
    if (textAfterChange.length > kMax2FAPinLength) {
        textAfterChange = [textAfterChange substringToIndex:kMax2FAPinLength];
    }
    // 6. Construct the final text.
    textField.text = textAfterChange;
    NSUInteger cursorPositionAfterChange = MIN(left.length + center.length, textAfterChange.length);
    UITextPosition *pos =
        [textField positionFromPosition:textField.beginningOfDocument offset:(NSInteger)cursorPositionAfterChange];
    [textField setSelectedTextRange:[textField textRangeFromPosition:pos toPosition:pos]];
}

+ (NSString *)examplePhoneNumberForCountryCode:(NSString *)countryCode callingCode:(NSString *)callingCode
{
    OWSAssertDebug(countryCode.length > 0);
    OWSAssertDebug(callingCode.length > 0);

    NSString *examplePhoneNumber = [PhoneNumberUtil examplePhoneNumberForCountryCode:countryCode];
    OWSAssertDebug(!examplePhoneNumber || [examplePhoneNumber hasPrefix:callingCode]);
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

@end

NS_ASSUME_NONNULL_END
