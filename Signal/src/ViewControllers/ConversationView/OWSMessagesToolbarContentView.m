//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessagesToolbarContentView.h"
#import "UIColor+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessagesToolbarContentView () <UIGestureRecognizerDelegate>

@property (nonatomic) BOOL shouldShowVoiceMemoButton;

@property (nonatomic, nullable) UIButton *voiceMemoButton;

@property (nonatomic, nullable) UIButton *sendButton;

@property (nonatomic) BOOL isRecordingVoiceMemo;

@property (nonatomic) CGPoint voiceMemoGestureStartLocation;

@end

#pragma mark -

@implementation OWSMessagesToolbarContentView

#pragma mark - Class methods

+ (UINib *)nib
{
    return [UINib nibWithNibName:NSStringFromClass([OWSMessagesToolbarContentView class])
                          bundle:[NSBundle bundleForClass:[OWSMessagesToolbarContentView class]]];
}

- (void)ensureSubviews
{
    if (!self.sendButton) {
        OWSAssert(self.rightBarButtonItem);

        self.sendButton = self.rightBarButtonItem;
    }

    if (!self.voiceMemoButton) {
        UIImage *icon = [UIImage imageNamed:@"voice-memo-button"];
        OWSAssert(icon);
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        [button setImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                forState:UIControlStateNormal];
        button.imageView.tintColor = [UIColor ows_materialBlueColor];

        // We want to be permissive about the voice message gesture, so we:
        //
        // * Add the gesture recognizer to the button's superview instead of the button.
        // * Filter the touches that the gesture recognizer receives by serving as its
        //   delegate.
        UILongPressGestureRecognizer *longPressGestureRecognizer =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPressGestureRecognizer.minimumPressDuration = 0;
        longPressGestureRecognizer.delegate = self;
        [self addGestureRecognizer:longPressGestureRecognizer];

        // We want to be permissive about taps on the send button, so we:
        //
        // * Add the gesture recognizer to the button's superview instead of the button.
        // * Filter the touches that the gesture recognizer receives by serving as its
        //   delegate.
        UITapGestureRecognizer *tapGestureRecognizer =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        tapGestureRecognizer.delegate = self;
        [self addGestureRecognizer:tapGestureRecognizer];

        self.userInteractionEnabled = YES;

        self.voiceMemoButton = button;
    }

    [self ensureShouldShowVoiceMemoButton];

    [self ensureVoiceMemoButton];
}

- (void)ensureEnabling
{
    [self ensureShouldShowVoiceMemoButton];

    OWSAssert(self.voiceMemoButton.isEnabled == YES);
    OWSAssert(self.sendButton.isEnabled == YES);
}

- (void)ensureShouldShowVoiceMemoButton
{
    self.shouldShowVoiceMemoButton = self.textView.text.length < 1;
}

- (void)setShouldShowVoiceMemoButton:(BOOL)shouldShowVoiceMemoButton
{
    if (_shouldShowVoiceMemoButton == shouldShowVoiceMemoButton) {
        return;
    }

    _shouldShowVoiceMemoButton = shouldShowVoiceMemoButton;

    [self ensureVoiceMemoButton];
}

- (void)ensureVoiceMemoButton
{
    if (self.shouldShowVoiceMemoButton) {
        self.rightBarButtonItem = self.voiceMemoButton;
        self.rightBarButtonItemWidth = [self.voiceMemoButton sizeThatFits:CGSizeZero].width;
    } else {
        self.rightBarButtonItem = self.sendButton;
        self.rightBarButtonItemWidth = [self.sendButton sizeThatFits:CGSizeZero].width;
    }
}

- (void)handleLongPress:(UIGestureRecognizer *)sender
{
    switch (sender.state) {
        case UIGestureRecognizerStatePossible:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            if (self.isRecordingVoiceMemo) {
                // Cancel voice message if necessary.
                self.isRecordingVoiceMemo = NO;
                [self.voiceMemoGestureDelegate voiceMemoGestureDidCancel];
            }
            break;
        case UIGestureRecognizerStateBegan:
            if (self.isRecordingVoiceMemo) {
                // Cancel voice message if necessary.
                self.isRecordingVoiceMemo = NO;
                [self.voiceMemoGestureDelegate voiceMemoGestureDidCancel];
            }
            // Start voice message.
            self.isRecordingVoiceMemo = YES;
            self.voiceMemoGestureStartLocation = [sender locationInView:self];
            [self.voiceMemoGestureDelegate voiceMemoGestureDidStart];
            break;
        case UIGestureRecognizerStateChanged:
            if (self.isRecordingVoiceMemo) {
                // Check for "slide to cancel" gesture.
                CGPoint location = [sender locationInView:self];
                CGFloat offset = fabs(self.voiceMemoGestureStartLocation.x - location.x);
                // The lower this value, the easier it is to cancel by accident.
                // The higher this value, the harder it is to cancel.
                const CGFloat kCancelOffsetPoints = 100.f;
                CGFloat cancelAlpha = offset / kCancelOffsetPoints;
                BOOL isCancelled = cancelAlpha >= 1.f;
                if (isCancelled) {
                    self.isRecordingVoiceMemo = NO;
                    [self.voiceMemoGestureDelegate voiceMemoGestureDidCancel];
                } else {
                    [self.voiceMemoGestureDelegate voiceMemoGestureDidChange:cancelAlpha];
                }
            }
            break;
        case UIGestureRecognizerStateEnded:
            if (self.isRecordingVoiceMemo) {
                // End voice message.
                self.isRecordingVoiceMemo = NO;
                [self.voiceMemoGestureDelegate voiceMemoGestureDidEnd];
            }
            break;
    }
}

- (void)handleTap:(UIGestureRecognizer *)sender
{
    switch (sender.state) {
        case UIGestureRecognizerStateRecognized:
            [self.sendMessageGestureDelegate sendMessageGestureRecognized];
            break;
        default:
            break;
    }
}

- (void)cancelVoiceMemoIfNecessary
{
    if (self.isRecordingVoiceMemo) {
        self.isRecordingVoiceMemo = NO;
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if ([gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        if (self.rightBarButtonItem != self.voiceMemoButton) {
            return NO;
        }

        // We want to be permissive about the voice message gesture, so we accept
        // gesture that begin within N points of its bounds.
        CGFloat kVoiceMemoGestureTolerancePoints = 10;
        CGPoint location = [touch locationInView:self.voiceMemoButton];
        CGRect hitTestRect = CGRectInset(
            self.voiceMemoButton.bounds, -kVoiceMemoGestureTolerancePoints, -kVoiceMemoGestureTolerancePoints);
        return CGRectContainsPoint(hitTestRect, location);
    } else if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        if (self.rightBarButtonItem == self.voiceMemoButton) {
            return NO;
        }

        UIView *sendButton = self.rightBarButtonItem;
        // We want to be permissive about taps on the send button, so we accept
        // gesture that begin within N points of its bounds.
        CGFloat kSendButtonTolerancePoints = 10;
        CGPoint location = [touch locationInView:sendButton];
        CGRect hitTestRect = CGRectInset(sendButton.bounds, -kSendButtonTolerancePoints, -kSendButtonTolerancePoints);
        return CGRectContainsPoint(hitTestRect, location);
    } else {
        return YES;
    }
}

@end

NS_ASSUME_NONNULL_END
