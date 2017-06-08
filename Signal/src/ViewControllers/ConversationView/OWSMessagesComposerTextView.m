//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessagesComposerTextView.h"
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSMessagesComposerTextView

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)pasteboardHasPossibleAttachment
{
    // We don't want to load/convert images more than once so we
    // only do a cursory validation pass at this time.
    return ([SignalAttachment pasteboardHasPossibleAttachment] && ![SignalAttachment pasteboardHasText]);
}

- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender
{
    if (action == @selector(paste:)) {
        if ([self pasteboardHasPossibleAttachment]) {
            return YES;
        }
    }
    return [super canPerformAction:action withSender:sender];
}

- (void)paste:(nullable id)sender
{
    if ([self pasteboardHasPossibleAttachment]) {
        SignalAttachment *attachment = [SignalAttachment attachmentFromPasteboard];
        // Note: attachment might be nil or have an error at this point; that's fine.
        [self.textViewPasteDelegate didPasteAttachment:attachment];
        return;
    }

    [super paste:sender];
}

- (void)setFrame:(CGRect)frame
{
    BOOL isNonEmpty = (self.width > 0.f && self.height > 0.f);
    BOOL didChangeSize = !CGSizeEqualToSize(frame.size, self.frame.size);

    [super setFrame:frame];

    if (didChangeSize && isNonEmpty) {
        [self.textViewPasteDelegate textViewDidChangeSize];
    }
}

- (void)setBounds:(CGRect)bounds
{
    BOOL isNonEmpty = (self.width > 0.f && self.height > 0.f);
    BOOL didChangeSize = !CGSizeEqualToSize(bounds.size, self.bounds.size);

    [super setBounds:bounds];

    if (didChangeSize && isNonEmpty) {
        [self.textViewPasteDelegate textViewDidChangeSize];
    }
}

@end

NS_ASSUME_NONNULL_END
