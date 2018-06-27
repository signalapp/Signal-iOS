//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageTextView.h"
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSMessageTextView

// Our message text views are never used for editing;
// suppress their ability to become first responder
// so that tapping on them doesn't hide keyboard.
- (BOOL)canBecomeFirstResponder
{
    return NO;
}

// Ignore interactions with the text view _except_ taps on links.
//
// We want to disable "partial" selection of text in the message
// and we want to enable "tap to resend" by tapping on a message.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *_Nullable)event
{
    if (self.shouldIgnoreEvents) {
        // We ignore all events for failed messages so that users
        // can tap-to-resend even "all link" messages.
        return NO;
    }

    // Find the nearest text position to the event.
    UITextPosition *_Nullable position = [self closestPositionToPoint:point];
    if (!position) {
        return NO;
    }
    // Find the range of the character in the text which contains the event.
    //
    // Try every layout direction (this might not be necessary).
    UITextRange *_Nullable range = nil;
    for (NSNumber *textLayoutDirection in @[
             @(UITextLayoutDirectionLeft),
             @(UITextLayoutDirectionRight),
             @(UITextLayoutDirectionUp),
             @(UITextLayoutDirectionDown),
         ]) {
        range = [self.tokenizer rangeEnclosingPosition:position
                                       withGranularity:UITextGranularityCharacter
                                           inDirection:(UITextDirection)textLayoutDirection.intValue];
        if (range) {
            break;
        }
    }
    if (!range) {
        return NO;
    }
    // Ignore the event unless it occurred inside a link.
    NSInteger startIndex = [self offsetFromPosition:self.beginningOfDocument toPosition:range.start];
    BOOL result =
        [self.attributedText attribute:NSLinkAttributeName atIndex:(NSUInteger)startIndex effectiveRange:nil] != nil;
    return result;
}

// TODO: Add unit test.
- (CGSize)compactSizeThatFitsMaxWidth:(CGFloat)maxWidth maxIterations:(NSUInteger)maxIterations
{
    OWSAssert(maxWidth > 0);

    CGSize textSize = CGSizeCeil([self sizeThatFits:CGSizeMake(maxWidth, CGFLOAT_MAX)]);

    // "Compact" layout to reduce "widows",
    // e.g. last lines with only a single word.
    //
    // After measuring the size of the text, we try to find smaller widths
    // in which the text will fit without adding any height, by wrapping
    // more text onto the last line. We use a binary search.
    if (textSize.width > 0 && textSize.height > 0) {
        NSUInteger upperBound = (NSUInteger)textSize.width;
        NSUInteger lowerBound = 1;
        // The more iterations we perform in our binary search,
        // the more accurate the result, but the more expensive
        // layout becomes.
        for (NSUInteger i = 0; i < maxIterations; i++) {
            NSUInteger resizeWidth = (upperBound + lowerBound) / 2;
            if (resizeWidth >= upperBound || resizeWidth <= lowerBound) {
                break;
            }
            CGSize resizeSize = CGSizeCeil([self sizeThatFits:CGSizeMake(resizeWidth, CGFLOAT_MAX)]);
            BOOL success
                = (resizeSize.width > 0 && resizeSize.width <= resizeWidth && resizeSize.height <= textSize.height);
            if (success) {
                // Success.
                textSize = resizeSize;
                upperBound = (NSUInteger)textSize.width;
            } else {
                // Failure.
                lowerBound = resizeWidth;
            }
        }
    }
    textSize.width = MIN(textSize.width, maxWidth);
    return CGSizeCeil(textSize);
}

@end

NS_ASSUME_NONNULL_END
