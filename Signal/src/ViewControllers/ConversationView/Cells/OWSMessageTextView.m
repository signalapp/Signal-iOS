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

@end

NS_ASSUME_NONNULL_END
