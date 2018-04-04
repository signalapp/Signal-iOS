//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ConversationInputToolbar.h"
#import "ConversationInputTextView.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "OWSMath.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <SignalMessaging/OWSFormat.h>
#import <SignalServiceKit/NSTimer+OWS.h>
#import <SignalServiceKit/TSQuotedMessage.h>

NS_ASSUME_NONNULL_BEGIN

static void *kConversationInputTextViewObservingContext = &kConversationInputTextViewObservingContext;
static const CGFloat ConversationInputToolbarBorderViewHeight = 0.5;

#pragma mark -

@interface ConversationInputToolbar () <UIGestureRecognizerDelegate,
    ConversationTextViewToolbarDelegate,
    QuotedReplyPreviewDelegate>

@property (nonatomic, readonly) UIView *composeContainer;
@property (nonatomic, readonly) ConversationInputTextView *inputTextView;
@property (nonatomic, readonly) UIStackView *contentStackView;
@property (nonatomic, readonly) UIButton *attachmentButton;
@property (nonatomic, readonly) UIButton *sendButton;
@property (nonatomic, readonly) UIButton *voiceMemoButton;
@property (nonatomic, readonly) UIView *leftButtonWrapper;
@property (nonatomic, readonly) UIView *rightButtonWrapper;

@property (nonatomic) BOOL shouldShowVoiceMemoButton;

@property (nonatomic) NSArray<NSLayoutConstraint *> *contentContraints;
@property (nonatomic) NSValue *lastTextContentSize;
@property (nonatomic) CGFloat toolbarHeight;
@property (nonatomic) CGFloat textViewHeight;

#pragma mark -

@property (nonatomic, nullable) QuotedReplyPreview *quotedMessagePreview;

#pragma mark - Voice Memo Recording UI

@property (nonatomic, nullable) UIView *voiceMemoUI;
@property (nonatomic, nullable) UIView *voiceMemoContentView;
@property (nonatomic) NSDate *voiceMemoStartTime;
@property (nonatomic, nullable) NSTimer *voiceMemoUpdateTimer;
@property (nonatomic, nullable) UILabel *recordingLabel;
@property (nonatomic) BOOL isRecordingVoiceMemo;
@property (nonatomic) CGPoint voiceMemoGestureStartLocation;

@end

#pragma mark -


#pragma mark -

@implementation ConversationInputToolbar

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self createContents];
    }

    return self;
}

- (void)dealloc
{
    [self removeKVOObservers];
}

- (CGSize)intrinsicContentSize
{
    // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, the intrinsicContentSize is used
    // to determine the height of the rendered inputAccessoryView.
    CGFloat height = self.toolbarHeight + ConversationInputToolbarBorderViewHeight;
    if (self.quotedMessagePreview) {
        height += self.quotedMessagePreview.intrinsicContentSize.height;
    }
    CGSize newSize = CGSizeMake(self.bounds.size.width, height);

    return newSize;
}

- (void)createContents
{
    self.layoutMargins = UIEdgeInsetsZero;

    self.backgroundColor = [UIColor ows_toolbarBackgroundColor];
    self.autoresizingMask = UIViewAutoresizingFlexibleHeight;

    UIView *borderView = [UIView new];
    borderView.backgroundColor = [UIColor colorWithWhite:238 / 255.f alpha:1.f];
    [self addSubview:borderView];
    [borderView autoPinWidthToSuperview];
    [borderView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [borderView autoSetDimension:ALDimensionHeight toSize:ConversationInputToolbarBorderViewHeight];

    _composeContainer = [UIView containerView];
    _contentStackView = [[UIStackView alloc] initWithArrangedSubviews:@[ _composeContainer ]];
    _contentStackView.axis = UILayoutConstraintAxisVertical;

    [self addSubview:_contentStackView];
    [_contentStackView autoPinEdgesToSuperviewEdges];

    _inputTextView = [ConversationInputTextView new];
    self.inputTextView.textViewToolbarDelegate = self;
    self.inputTextView.font = [UIFont ows_dynamicTypeBodyFont];
    [self.composeContainer addSubview:self.inputTextView];

    // We want to be permissive about taps on the send and attachment buttons,
    // so we use wrapper views that capture nearby taps.  This is a lot easier
    // than trying to manipulate the size of the buttons themselves, as you
    // can't coordinate the layout of the button content (e.g. image or text)
    // using iOS auto layout.
    _leftButtonWrapper = [UIView containerView];
    [self.leftButtonWrapper
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(leftButtonTapped:)]];
    [self.composeContainer addSubview:self.leftButtonWrapper];
    _rightButtonWrapper = [UIView containerView];
    [self.rightButtonWrapper
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rightButtonTapped:)]];
    [self.composeContainer addSubview:self.rightButtonWrapper];

    _attachmentButton = [[UIButton alloc] init];
    self.attachmentButton.accessibilityLabel
        = NSLocalizedString(@"ATTACHMENT_LABEL", @"Accessibility label for attaching photos");
    self.attachmentButton.accessibilityHint = NSLocalizedString(
        @"ATTACHMENT_HINT", @"Accessibility hint describing what you can do with the attachment button");
    [self.attachmentButton addTarget:self
                              action:@selector(attachmentButtonPressed)
                    forControlEvents:UIControlEventTouchUpInside];
    [self.attachmentButton setImage:[UIImage imageNamed:@"btnAttachments--blue"] forState:UIControlStateNormal];
    self.attachmentButton.contentEdgeInsets = UIEdgeInsetsMake(0, 3, 0, 3);
    [self.leftButtonWrapper addSubview:self.attachmentButton];

    // TODO: Fix layout in this class.
    _sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.sendButton
        setTitle:NSLocalizedString(@"SEND_BUTTON_TITLE", @"Label for the send button in the conversation view.")
        forState:UIControlStateNormal];
    [self.sendButton setTitleColor:[UIColor ows_materialBlueColor] forState:UIControlStateNormal];
    self.sendButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.sendButton.titleLabel.font = [UIFont ows_mediumFontWithSize:16.f];
    [self.sendButton addTarget:self action:@selector(sendButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.rightButtonWrapper addSubview:self.sendButton];

    UIImage *voiceMemoIcon = [UIImage imageNamed:@"voice-memo-button"];
    OWSAssert(voiceMemoIcon);
    _voiceMemoButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.voiceMemoButton setImage:[voiceMemoIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                          forState:UIControlStateNormal];
    self.voiceMemoButton.imageView.tintColor = [UIColor ows_materialBlueColor];
    [self.rightButtonWrapper addSubview:self.voiceMemoButton];

    // We want to be permissive about the voice message gesture, so we hang
    // the long press GR on the button's wrapper, not the button itself.
    UILongPressGestureRecognizer *longPressGestureRecognizer =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPressGestureRecognizer.minimumPressDuration = 0;
    longPressGestureRecognizer.delegate = self;
    [self.rightButtonWrapper addGestureRecognizer:longPressGestureRecognizer];

    self.userInteractionEnabled = YES;

    [self addKVOObservers];

    [self ensureShouldShowVoiceMemoButton];

    [self ensureContentConstraints];
}

- (void)updateFontSizes
{
    self.inputTextView.font = [UIFont ows_dynamicTypeBodyFont];

    [self ensureContentConstraints];
}

- (void)setInputTextViewDelegate:(id<ConversationInputTextViewDelegate>)value
{
    OWSAssert(self.inputTextView);
    OWSAssert(value);

    self.inputTextView.inputTextViewDelegate = value;
}

- (NSString *)messageText
{
    OWSAssert(self.inputTextView);

    return self.inputTextView.trimmedText;
}

- (void)setMessageText:(NSString *_Nullable)value
{
    OWSAssert(self.inputTextView);

    self.inputTextView.text = value;

    [self ensureShouldShowVoiceMemoButton];
}

- (void)clearTextMessage
{
    [self setMessageText:nil];
    [self.inputTextView.undoManager removeAllActions];
}

- (void)toggleDefaultKeyboard
{
    // Primary language is nil for the emoji keyboard.
    if (!self.inputTextView.textInputMode.primaryLanguage) {
        // Stay on emoji keyboard after sending
        return;
    }

    // Otherwise, we want to toggle back to default keyboard if the user had the numeric keyboard present.

    // Momentarily switch to a non-default keyboard, else reloadInputViews
    // will not affect the displayed keyboard. In practice this isn't perceptable to the user.
    // The alternative would be to dismiss-and-pop the keyboard, but that can cause a more pronounced animation.
    self.inputTextView.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    [self.inputTextView reloadInputViews];

    self.inputTextView.keyboardType = UIKeyboardTypeDefault;
    [self.inputTextView reloadInputViews];
}

- (void)setShouldShowVoiceMemoButton:(BOOL)shouldShowVoiceMemoButton
{
    if (_shouldShowVoiceMemoButton == shouldShowVoiceMemoButton) {
        return;
    }

    _shouldShowVoiceMemoButton = shouldShowVoiceMemoButton;

    [self ensureContentConstraints];
}

- (void)setQuotedMessage:(nullable TSQuotedMessage *)quotedMessage
{
    if (quotedMessage == _quotedMessage) {
        return;
    }

    // TODO update existing preview with message in case we switch which message we're quoting.
    if (self.quotedMessagePreview) {
        [self clearQuotedMessagePreview];
    }
    OWSAssert(self.quotedMessagePreview == nil);

    _quotedMessage = quotedMessage;

    if (!quotedMessage) {
        [self clearQuotedMessagePreview];
        return;
    }

    self.quotedMessagePreview = [[QuotedReplyPreview alloc] initWithQuotedMessage:quotedMessage];
    self.quotedMessagePreview.delegate = self;

    // TODO animate
    [self.contentStackView insertArrangedSubview:self.quotedMessagePreview atIndex:0];
}

- (void)clearQuotedMessagePreview
{
    // TODO animate
    if (self.quotedMessagePreview) {
        [self.contentStackView removeArrangedSubview:self.quotedMessagePreview];
        [self.quotedMessagePreview removeFromSuperview];
        self.quotedMessagePreview = nil;
    }
}

- (void)beginEditingTextMessage
{
    [self.inputTextView becomeFirstResponder];
}

- (void)endEditingTextMessage
{
    [self.inputTextView resignFirstResponder];
}

- (BOOL)isInputTextViewFirstResponder
{
    return self.inputTextView.isFirstResponder;
}

- (void)ensureContentConstraints
{
    [NSLayoutConstraint deactivateConstraints:self.contentContraints];

    const int textViewVInset = 5;
    const int contentHInset = 6;
    const int contentHSpacing = 6;

    // We want to grow the text input area to fit its content within reason.
    const CGFloat kMinTextViewHeight = ceil(self.inputTextView.font.lineHeight
        + self.inputTextView.textContainerInset.top + self.inputTextView.textContainerInset.bottom
        + self.inputTextView.contentInset.top + self.inputTextView.contentInset.bottom);
    // Exactly 4 lines of text with default sizing.
    const CGFloat kMaxTextViewHeight = 98.f;
    const CGFloat textViewDesiredHeight = (self.inputTextView.contentSize.height + self.inputTextView.contentInset.top
        + self.inputTextView.contentInset.bottom);
    const CGFloat textViewHeight = ceil(Clamp(textViewDesiredHeight, kMinTextViewHeight, kMaxTextViewHeight));
    const CGFloat kMinContentHeight = kMinTextViewHeight + textViewVInset * 2;

    self.textViewHeight = textViewHeight;
    self.toolbarHeight = textViewHeight + textViewVInset * 2;

    self.leftButtonWrapper.hidden = NO;
    self.inputTextView.hidden = NO;
    self.voiceMemoButton.hidden = NO;

    UIButton *leftButton = self.attachmentButton;
    UIButton *rightButton = (self.shouldShowVoiceMemoButton ? self.voiceMemoButton : self.sendButton);
    UIButton *inactiveRightButton = (self.shouldShowVoiceMemoButton ? self.sendButton : self.voiceMemoButton);
    leftButton.enabled = YES;
    rightButton.enabled = YES;
    inactiveRightButton.enabled = NO;
    leftButton.hidden = NO;
    rightButton.hidden = NO;
    inactiveRightButton.hidden = YES;

    [leftButton setContentHuggingHigh];
    [rightButton setContentHuggingHigh];
    [leftButton setCompressionResistanceHigh];
    [rightButton setCompressionResistanceHigh];
    [self.inputTextView setCompressionResistanceLow];
    [self.inputTextView setContentHuggingLow];

    OWSAssert(leftButton.superview == self.leftButtonWrapper);
    OWSAssert(rightButton.superview == self.rightButtonWrapper);

    // The leading and trailing buttons should be center-aligned with the
    // inputTextView when the inputTextView is at its minimum size.
    //
    // We want the leading and trailing buttons to hug the bottom of the input
    // toolbar as the inputTextView expands.
    //
    // Therefore we fix the button heights to the size of the toolbar when
    // inputTextView is at its minimum size.
    //
    // Additionally, we use "wrapper" views around the leading and trailing
    // buttons to expand their hot area.
    self.contentContraints = @[
        [self.leftButtonWrapper autoPinEdgeToSuperviewEdge:ALEdgeLeft],
        [self.leftButtonWrapper autoPinEdgeToSuperviewEdge:ALEdgeTop],
        [self.leftButtonWrapper autoPinBottomToSuperviewMarginWithInset:0],

        [leftButton autoSetDimension:ALDimensionHeight toSize:kMinContentHeight],
        [leftButton autoPinLeadingToSuperviewMarginWithInset:contentHInset],
        [leftButton autoPinTrailingToSuperviewMarginWithInset:contentHSpacing],
        [leftButton autoPinEdgeToSuperviewEdge:ALEdgeBottom],

        [self.inputTextView autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:self.leftButtonWrapper],
        [self.inputTextView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:textViewVInset],
        [self.inputTextView autoPinBottomToSuperviewMarginWithInset:textViewVInset],
        [self.inputTextView autoSetDimension:ALDimensionHeight toSize:textViewHeight],

        [self.rightButtonWrapper autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:self.inputTextView],
        [self.rightButtonWrapper autoPinEdgeToSuperviewEdge:ALEdgeRight],
        [self.rightButtonWrapper autoPinEdgeToSuperviewEdge:ALEdgeTop],
        [self.rightButtonWrapper autoPinBottomToSuperviewMarginWithInset:0],

        [rightButton autoSetDimension:ALDimensionHeight toSize:kMinContentHeight],
        [rightButton autoPinLeadingToSuperviewMarginWithInset:contentHSpacing],
        [rightButton autoPinTrailingToSuperviewMarginWithInset:contentHInset],
        [rightButton autoPinEdgeToSuperviewEdge:ALEdgeBottom]
    ];

    // Layout immediately, unless the input toolbar hasn't even been laid out yet.
    if (self.bounds.size.width > 0 && self.bounds.size.height > 0) {
        [self layoutIfNeeded];
    }
}

- (void)ensureShouldShowVoiceMemoButton
{
    self.shouldShowVoiceMemoButton = self.inputTextView.trimmedText.length < 1;
}

- (void)handleLongPress:(UIGestureRecognizer *)sender
{
    if (!self.shouldShowVoiceMemoButton) {
        return;
    }

    switch (sender.state) {
        case UIGestureRecognizerStatePossible:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            if (self.isRecordingVoiceMemo) {
                // Cancel voice message if necessary.
                self.isRecordingVoiceMemo = NO;
                [self.inputToolbarDelegate voiceMemoGestureDidCancel];
            }
            break;
        case UIGestureRecognizerStateBegan:
            if (self.isRecordingVoiceMemo) {
                // Cancel voice message if necessary.
                self.isRecordingVoiceMemo = NO;
                [self.inputToolbarDelegate voiceMemoGestureDidCancel];
            }
            // Start voice message.
            self.isRecordingVoiceMemo = YES;
            self.voiceMemoGestureStartLocation = [sender locationInView:self];
            [self.inputToolbarDelegate voiceMemoGestureDidStart];
            break;
        case UIGestureRecognizerStateChanged:
            if (self.isRecordingVoiceMemo) {
                // Check for "slide to cancel" gesture.
                CGPoint location = [sender locationInView:self];
                // For LTR/RTL, swiping in either direction will cancel.
                // This is okay because there's only space on screen to perform the
                // gesture in one direction.
                CGFloat offset = fabs(self.voiceMemoGestureStartLocation.x - location.x);
                // The lower this value, the easier it is to cancel by accident.
                // The higher this value, the harder it is to cancel.
                const CGFloat kCancelOffsetPoints = 100.f;
                CGFloat cancelAlpha = offset / kCancelOffsetPoints;
                BOOL isCancelled = cancelAlpha >= 1.f;
                if (isCancelled) {
                    self.isRecordingVoiceMemo = NO;
                    [self.inputToolbarDelegate voiceMemoGestureDidCancel];
                } else {
                    [self.inputToolbarDelegate voiceMemoGestureDidChange:cancelAlpha];
                }
            }
            break;
        case UIGestureRecognizerStateEnded:
            if (self.isRecordingVoiceMemo) {
                // End voice message.
                self.isRecordingVoiceMemo = NO;
                [self.inputToolbarDelegate voiceMemoGestureDidEnd];
            }
            break;
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if ([gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return self.shouldShowVoiceMemoButton;
    } else {
        return YES;
    }
}

#pragma mark - Voice Memo

- (void)showVoiceMemoUI
{
    OWSAssertIsOnMainThread();

    self.voiceMemoStartTime = [NSDate date];

    [self.voiceMemoUI removeFromSuperview];

    self.voiceMemoUI = [UIView new];
    self.voiceMemoUI.userInteractionEnabled = NO;
    self.voiceMemoUI.backgroundColor = [UIColor whiteColor];
    [self addSubview:self.voiceMemoUI];
    self.voiceMemoUI.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);

    self.voiceMemoContentView = [UIView new];
    [self.voiceMemoUI addSubview:self.voiceMemoContentView];
    [self.voiceMemoContentView autoPinToSuperviewEdges];

    self.recordingLabel = [UILabel new];
    self.recordingLabel.textColor = [UIColor ows_destructiveRedColor];
    self.recordingLabel.font = [UIFont ows_mediumFontWithSize:14.f];
    [self.voiceMemoContentView addSubview:self.recordingLabel];
    [self updateVoiceMemo];

    UIImage *icon = [UIImage imageNamed:@"voice-memo-button"];
    OWSAssert(icon);
    UIImageView *imageView =
        [[UIImageView alloc] initWithImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    imageView.tintColor = [UIColor ows_destructiveRedColor];
    [self.voiceMemoContentView addSubview:imageView];

    NSMutableAttributedString *cancelString = [NSMutableAttributedString new];
    const CGFloat cancelArrowFontSize = ScaleFromIPhone5To7Plus(18.4, 20.f);
    const CGFloat cancelFontSize = ScaleFromIPhone5To7Plus(14.f, 16.f);
    NSString *arrowHead = (self.isRTL ? @"\uf105" : @"\uf104");
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:arrowHead
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                                           NSForegroundColorAttributeName : [UIColor ows_destructiveRedColor],
                                           NSBaselineOffsetAttributeName : @(-1.f),
                                       }]];
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:@"  "
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                                           NSForegroundColorAttributeName : [UIColor ows_destructiveRedColor],
                                           NSBaselineOffsetAttributeName : @(-1.f),
                                       }]];
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:NSLocalizedString(@"VOICE_MESSAGE_CANCEL_INSTRUCTIONS",
                                                      @"Indicates how to cancel a voice message.")
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_mediumFontWithSize:cancelFontSize],
                                           NSForegroundColorAttributeName : [UIColor ows_destructiveRedColor],
                                       }]];
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:@"  "
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                                           NSForegroundColorAttributeName : [UIColor ows_destructiveRedColor],
                                           NSBaselineOffsetAttributeName : @(-1.f),
                                       }]];
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:arrowHead
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                                           NSForegroundColorAttributeName : [UIColor ows_destructiveRedColor],
                                           NSBaselineOffsetAttributeName : @(-1.f),
                                       }]];
    UILabel *cancelLabel = [UILabel new];
    cancelLabel.attributedText = cancelString;
    [self.voiceMemoContentView addSubview:cancelLabel];

    const CGFloat kRedCircleSize = 100.f;
    UIView *redCircleView = [UIView new];
    redCircleView.backgroundColor = [UIColor ows_destructiveRedColor];
    redCircleView.layer.cornerRadius = kRedCircleSize * 0.5f;
    [redCircleView autoSetDimension:ALDimensionWidth toSize:kRedCircleSize];
    [redCircleView autoSetDimension:ALDimensionHeight toSize:kRedCircleSize];
    [self.voiceMemoContentView addSubview:redCircleView];
    [redCircleView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.voiceMemoButton];
    [redCircleView autoAlignAxis:ALAxisVertical toSameAxisOfView:self.voiceMemoButton];

    UIImage *whiteIcon = [UIImage imageNamed:@"voice-message-large-white"];
    OWSAssert(whiteIcon);
    UIImageView *whiteIconView = [[UIImageView alloc] initWithImage:whiteIcon];
    [redCircleView addSubview:whiteIconView];
    [whiteIconView autoCenterInSuperview];

    [imageView autoVCenterInSuperview];
    [imageView autoPinLeadingToSuperviewMarginWithInset:10.f];
    [self.recordingLabel autoVCenterInSuperview];
    [self.recordingLabel autoPinLeadingToTrailingEdgeOfView:imageView offset:5.f];
    [cancelLabel autoVCenterInSuperview];
    [cancelLabel autoHCenterInSuperview];
    [self.voiceMemoUI setNeedsLayout];
    [self.voiceMemoUI layoutSubviews];

    // Slide in the "slide to cancel" label.
    CGRect cancelLabelStartFrame = cancelLabel.frame;
    CGRect cancelLabelEndFrame = cancelLabel.frame;
    cancelLabelStartFrame.origin.x
        = (self.isRTL ? -self.voiceMemoUI.bounds.size.width : self.voiceMemoUI.bounds.size.width);
    cancelLabel.frame = cancelLabelStartFrame;
    [UIView animateWithDuration:0.35f
                          delay:0.f
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         cancelLabel.frame = cancelLabelEndFrame;
                     }
                     completion:nil];

    // Pulse the icon.
    imageView.layer.opacity = 1.f;
    [UIView animateWithDuration:0.5f
                          delay:0.2f
                        options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse
                        | UIViewAnimationOptionCurveEaseIn
                     animations:^{
                         imageView.layer.opacity = 0.f;
                     }
                     completion:nil];

    // Fade in the view.
    self.voiceMemoUI.layer.opacity = 0.f;
    [UIView animateWithDuration:0.2f
        animations:^{
            self.voiceMemoUI.layer.opacity = 1.f;
        }
        completion:^(BOOL finished) {
            if (finished) {
                self.voiceMemoUI.layer.opacity = 1.f;
            }
        }];

    [self.voiceMemoUpdateTimer invalidate];
    self.voiceMemoUpdateTimer = [NSTimer weakScheduledTimerWithTimeInterval:0.1f
                                                                     target:self
                                                                   selector:@selector(updateVoiceMemo)
                                                                   userInfo:nil
                                                                    repeats:YES];
}

- (void)hideVoiceMemoUI:(BOOL)animated
{
    OWSAssertIsOnMainThread();

    UIView *oldVoiceMemoUI = self.voiceMemoUI;
    self.voiceMemoUI = nil;
    self.voiceMemoContentView = nil;
    self.recordingLabel = nil;
    NSTimer *voiceMemoUpdateTimer = self.voiceMemoUpdateTimer;
    self.voiceMemoUpdateTimer = nil;

    [oldVoiceMemoUI.layer removeAllAnimations];

    if (animated) {
        [UIView animateWithDuration:0.35f
            animations:^{
                oldVoiceMemoUI.layer.opacity = 0.f;
            }
            completion:^(BOOL finished) {
                [oldVoiceMemoUI removeFromSuperview];
                [voiceMemoUpdateTimer invalidate];
            }];
    } else {
        [oldVoiceMemoUI removeFromSuperview];
        [voiceMemoUpdateTimer invalidate];
    }
}

- (void)setVoiceMemoUICancelAlpha:(CGFloat)cancelAlpha
{
    OWSAssertIsOnMainThread();

    // Fade out the voice message views as the cancel gesture
    // proceeds as feedback.
    self.voiceMemoContentView.layer.opacity = MAX(0.f, MIN(1.f, 1.f - (float)cancelAlpha));
}

- (void)updateVoiceMemo
{
    OWSAssertIsOnMainThread();

    NSTimeInterval durationSeconds = fabs([self.voiceMemoStartTime timeIntervalSinceNow]);
    self.recordingLabel.text = [OWSFormat formatDurationSeconds:(long)round(durationSeconds)];
    [self.recordingLabel sizeToFit];
}

- (void)cancelVoiceMemoIfNecessary
{
    if (self.isRecordingVoiceMemo) {
        self.isRecordingVoiceMemo = NO;
    }
}

#pragma mark - Event Handlers

- (void)leftButtonTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self attachmentButtonPressed];
    }
}

- (void)rightButtonTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        if (!self.shouldShowVoiceMemoButton) {
            [self sendButtonPressed];
        }
    }
}

- (void)sendButtonPressed
{
    OWSAssert(self.inputToolbarDelegate);

    [self.inputToolbarDelegate sendButtonPressed];
}

- (void)attachmentButtonPressed
{
    OWSAssert(self.inputToolbarDelegate);

    [self.inputToolbarDelegate attachmentButtonPressed];
}

#pragma mark - ConversationTextViewToolbarDelegate

- (void)textViewDidChange
{
    OWSAssert(self.inputToolbarDelegate);

    [self ensureShouldShowVoiceMemoButton];
}

#pragma mark - Text Input Sizing

- (void)addKVOObservers
{
    [self.inputTextView addObserver:self
                         forKeyPath:NSStringFromSelector(@selector(contentSize))
                            options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
                            context:kConversationInputTextViewObservingContext];
}

- (void)removeKVOObservers
{
    @try {
        [self.inputTextView removeObserver:self
                                forKeyPath:NSStringFromSelector(@selector(contentSize))
                                   context:kConversationInputTextViewObservingContext];
    } @catch (NSException *__unused exception) {
        // TODO: This try/catch can probably be safely removed.
        OWSFail(@"%@ removeKVOObservers failed.", self.logTag);
    }
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath
                      ofObject:(nullable id)object
                        change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(nullable void *)context
{
    if (context == kConversationInputTextViewObservingContext) {

        if (object == self.inputTextView && [keyPath isEqualToString:NSStringFromSelector(@selector(contentSize))]) {
            CGSize textContentSize = self.inputTextView.contentSize;
            NSValue *_Nullable lastTextContentSize = self.lastTextContentSize;
            self.lastTextContentSize = [NSValue valueWithCGSize:textContentSize];

            // Update view constraints, but only when text content size changes.
            //
            // NOTE: We use a "fuzzy equals" comparison to avoid infinite recursion,
            //       since ensureContentConstraints can affect the text content size.
            if (!lastTextContentSize || fabs(lastTextContentSize.CGSizeValue.width - textContentSize.width) > 0.1f
                || fabs(lastTextContentSize.CGSizeValue.height - textContentSize.height) > 0.1f) {
                [self ensureContentConstraints];
                [self invalidateIntrinsicContentSize];
            }
        }
    }
}

#pragma mark QuotedReplyPreviewViewDelegate

- (void)quotedReplyPreviewDidPressCancel:(QuotedReplyPreview *)preview
{
    self.quotedMessage = nil;
}

@end

NS_ASSUME_NONNULL_END
