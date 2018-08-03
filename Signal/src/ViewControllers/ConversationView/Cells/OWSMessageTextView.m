//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageTextView.h"
#import <SignalMessaging/UIView+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageTextView ()

@property (nonatomic, nullable) NSValue *cachedSize;

@end

#pragma mark -

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

- (void)setText:(nullable NSString *)text
{
    if ([NSObject isNullableObject:text equalTo:self.text]) {
        return;
    }
    [super setText:text];
    self.cachedSize = nil;
}

- (void)setAttributedText:(nullable NSAttributedString *)attributedText
{
    if ([NSObject isNullableObject:attributedText equalTo:self.attributedText]) {
        return;
    }
    [super setAttributedText:attributedText];
    self.cachedSize = nil;
}

- (void)setTextColor:(nullable UIColor *)textColor
{
    if ([NSObject isNullableObject:textColor equalTo:self.textColor]) {
        return;
    }
    [super setTextColor:textColor];
    // No need to clear cached size here.
}

- (void)setFont:(nullable UIFont *)font
{
    if ([NSObject isNullableObject:font equalTo:self.font]) {
        return;
    }
    [super setFont:font];
    self.cachedSize = nil;
}

- (void)setLinkTextAttributes:(nullable NSDictionary<NSString *, id> *)linkTextAttributes
{
    if ([NSObject isNullableObject:linkTextAttributes equalTo:self.linkTextAttributes]) {
        return;
    }
    [super setLinkTextAttributes:linkTextAttributes];
    self.cachedSize = nil;
}

- (CGSize)sizeThatFits:(CGSize)size
{
    if (self.cachedSize) {
        return self.cachedSize.CGSizeValue;
    }
    CGSize result = [super sizeThatFits:size];
    self.cachedSize = [NSValue valueWithCGSize:result];
    return result;
}

@end

NS_ASSUME_NONNULL_END
