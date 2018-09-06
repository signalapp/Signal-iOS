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

const CGFloat kMinTextViewHeight = 36;
const CGFloat kMaxTextViewHeight = 98;

#pragma mark -

@interface ConversationInputToolbar () <ConversationTextViewToolbarDelegate, QuotedReplyPreviewDelegate>

@property (nonatomic, readonly) ConversationStyle *conversationStyle;

@property (nonatomic, readonly) ConversationInputTextView *inputTextView;
@property (nonatomic, readonly) UIStackView *contentRows;
@property (nonatomic, readonly) UIStackView *composeRow;
@property (nonatomic, readonly) UIButton *attachmentButton;
@property (nonatomic, readonly) UIButton *sendButton;
@property (nonatomic, readonly) UIButton *voiceMemoButton;

@property (nonatomic) CGFloat textViewHeight;
@property (nonatomic, readonly) NSLayoutConstraint *textViewHeightConstraint;

#pragma mark -

@property (nonatomic, nullable) UIView *quotedMessagePreview;

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

- (instancetype)initWithConversationStyle:(ConversationStyle *)conversationStyle
{
    self = [super initWithFrame:CGRectZero];

    _conversationStyle = conversationStyle;
    
    if (self) {
        [self createContents];
    }
    
    return self;
}

- (CGSize)intrinsicContentSize
{
    // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
    // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
    return CGSizeZero;
}

- (void)createContents
{
    self.layoutMargins = UIEdgeInsetsZero;

    if (UIAccessibilityIsReduceTransparencyEnabled()) {
        self.backgroundColor = Theme.toolbarBackgroundColor;
    } else {
        CGFloat alpha = OWSNavigationBar.backgroundBlurMutingFactor;
        self.backgroundColor = [Theme.toolbarBackgroundColor colorWithAlphaComponent:alpha];

        UIVisualEffectView *blurEffectView = [[UIVisualEffectView alloc] initWithEffect:Theme.barBlurEffect];
        blurEffectView.layer.zPosition = -1;
        [self addSubview:blurEffectView];
        [blurEffectView autoPinEdgesToSuperviewEdges];
    }

    self.autoresizingMask = UIViewAutoresizingFlexibleHeight;

    _inputTextView = [ConversationInputTextView new];
    self.inputTextView.layer.cornerRadius = kMinTextViewHeight / 2.0f;
    self.inputTextView.textViewToolbarDelegate = self;
    self.inputTextView.font = [UIFont ows_dynamicTypeBodyFont];
    [self.inputTextView setContentHuggingHorizontalLow];

    _textViewHeightConstraint = [self.inputTextView autoSetDimension:ALDimensionHeight toSize:kMinTextViewHeight];

    _attachmentButton = [[UIButton alloc] init];
    self.attachmentButton.accessibilityLabel
        = NSLocalizedString(@"ATTACHMENT_LABEL", @"Accessibility label for attaching photos");
    self.attachmentButton.accessibilityHint = NSLocalizedString(
        @"ATTACHMENT_HINT", @"Accessibility hint describing what you can do with the attachment button");
    [self.attachmentButton addTarget:self
                              action:@selector(attachmentButtonPressed)
                    forControlEvents:UIControlEventTouchUpInside];
    UIImage *attachmentImage = [UIImage imageNamed:@"ic_circled_plus"];
    [self.attachmentButton setImage:[attachmentImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                           forState:UIControlStateNormal];
    self.attachmentButton.tintColor = Theme.navbarIconColor;
    [self.attachmentButton autoSetDimensionsToSize:CGSizeMake(40, kMinTextViewHeight)];

    _sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.sendButton
        setTitle:NSLocalizedString(@"SEND_BUTTON_TITLE", @"Label for the send button in the conversation view.")
        forState:UIControlStateNormal];
    [self.sendButton setTitleColor:UIColor.ows_signalBlueColor forState:UIControlStateNormal];
    self.sendButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.sendButton.titleLabel.font = [UIFont ows_mediumFontWithSize:17.f];
    self.sendButton.contentEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 4);
    [self.sendButton autoSetDimension:ALDimensionHeight toSize:kMinTextViewHeight];
    [self.sendButton addTarget:self action:@selector(sendButtonPressed) forControlEvents:UIControlEventTouchUpInside];

    UIImage *voiceMemoIcon = [UIImage imageNamed:@"voice-memo-button"];
    OWSAssertDebug(voiceMemoIcon);
    _voiceMemoButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.voiceMemoButton setImage:[voiceMemoIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                          forState:UIControlStateNormal];
    self.voiceMemoButton.imageView.tintColor = Theme.navbarIconColor;
    [self.voiceMemoButton autoSetDimensionsToSize:CGSizeMake(40, kMinTextViewHeight)];

    // We want to be permissive about the voice message gesture, so we hang
    // the long press GR on the button's wrapper, not the button itself.
    UILongPressGestureRecognizer *longPressGestureRecognizer =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPressGestureRecognizer.minimumPressDuration = 0;
    [self.voiceMemoButton addGestureRecognizer:longPressGestureRecognizer];

    self.userInteractionEnabled = YES;

    _composeRow = [[UIStackView alloc]
        initWithArrangedSubviews:@[ self.attachmentButton, self.inputTextView, self.voiceMemoButton, self.sendButton ]];
    self.composeRow.axis = UILayoutConstraintAxisHorizontal;
    self.composeRow.layoutMarginsRelativeArrangement = YES;
    self.composeRow.layoutMargins = UIEdgeInsetsMake(6, 6, 6, 6);
    self.composeRow.alignment = UIStackViewAlignmentBottom;
    self.composeRow.spacing = 8;

    _contentRows = [[UIStackView alloc] initWithArrangedSubviews:@[ self.composeRow ]];
    self.contentRows.axis = UILayoutConstraintAxisVertical;

    [self addSubview:self.contentRows];
    [self.contentRows autoPinEdgesToSuperviewEdges];

    [self ensureShouldShowVoiceMemoButtonAnimated:NO];
}

- (void)updateFontSizes
{
    self.inputTextView.font = [UIFont ows_dynamicTypeBodyFont];
}

- (void)setInputTextViewDelegate:(id<ConversationInputTextViewDelegate>)value
{
    OWSAssertDebug(self.inputTextView);
    OWSAssertDebug(value);

    self.inputTextView.inputTextViewDelegate = value;
}

- (NSString *)messageText
{
    OWSAssertDebug(self.inputTextView);

    return self.inputTextView.trimmedText;
}

- (void)setMessageText:(NSString *_Nullable)value animated:(BOOL)isAnimated
{
    OWSAssertDebug(self.inputTextView);

    self.inputTextView.text = value;

    [self ensureShouldShowVoiceMemoButtonAnimated:isAnimated];
    [self ensureTextViewHeight];
}

- (void)ensureTextViewHeight
{
    [self updateHeightWithTextView:self.inputTextView];
}

- (void)clearTextMessageAnimated:(BOOL)isAnimated
{
    [self setMessageText:nil animated:isAnimated];
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

- (void)setQuotedReply:(nullable OWSQuotedReplyModel *)quotedReply
{
    if (quotedReply == _quotedReply) {
        return;
    }

    if (self.quotedMessagePreview) {
        [self clearQuotedMessagePreview];
    }
    OWSAssertDebug(self.quotedMessagePreview == nil);

    _quotedReply = quotedReply;

    if (!quotedReply) {
        [self clearQuotedMessagePreview];
        return;
    }

    QuotedReplyPreview *quotedMessagePreview =
        [[QuotedReplyPreview alloc] initWithQuotedReply:quotedReply conversationStyle:self.conversationStyle];
    quotedMessagePreview.delegate = self;

    UIView *wrapper = [UIView containerView];
    wrapper.layoutMargins = UIEdgeInsetsMake(self.quotedMessageTopMargin, 0, 0, 0);
    [wrapper addSubview:quotedMessagePreview];
    [quotedMessagePreview ows_autoPinToSuperviewMargins];

    [self.contentRows insertArrangedSubview:wrapper atIndex:0];

    self.quotedMessagePreview = wrapper;
}

- (CGFloat)quotedMessageTopMargin
{
    return 5.f;
}

- (void)clearQuotedMessagePreview
{
    if (self.quotedMessagePreview) {
        [self.contentRows removeArrangedSubview:self.quotedMessagePreview];
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

- (void)ensureShouldShowVoiceMemoButtonAnimated:(BOOL)isAnimated
{
    void (^updateBlock)(void) = ^{
        if (self.inputTextView.trimmedText.length > 0) {
            if (!self.voiceMemoButton.isHidden) {
                self.voiceMemoButton.hidden = YES;
            }

            if (self.sendButton.isHidden) {
                self.sendButton.hidden = NO;
            }
        } else {
            if (self.voiceMemoButton.isHidden) {
                self.voiceMemoButton.hidden = NO;
            }

            if (!self.sendButton.isHidden) {
                self.sendButton.hidden = YES;
            }
        }
        [self layoutIfNeeded];
    };

    if (isAnimated) {
        [UIView animateWithDuration:0.1 animations:updateBlock];
    } else {
        updateBlock();
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

#pragma mark - Voice Memo

- (void)showVoiceMemoUI
{
    OWSAssertIsOnMainThread();

    self.voiceMemoStartTime = [NSDate date];

    [self.voiceMemoUI removeFromSuperview];

    self.voiceMemoUI = [UIView new];
    self.voiceMemoUI.userInteractionEnabled = NO;
    self.voiceMemoUI.backgroundColor = Theme.toolbarBackgroundColor;
    [self addSubview:self.voiceMemoUI];
    self.voiceMemoUI.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);

    self.voiceMemoContentView = [UIView new];
    [self.voiceMemoUI addSubview:self.voiceMemoContentView];
    [self.voiceMemoContentView ows_autoPinToSuperviewEdges];

    self.recordingLabel = [UILabel new];
    self.recordingLabel.textColor = [UIColor ows_destructiveRedColor];
    self.recordingLabel.font = [UIFont ows_mediumFontWithSize:14.f];
    [self.voiceMemoContentView addSubview:self.recordingLabel];
    [self updateVoiceMemo];

    UIImage *icon = [UIImage imageNamed:@"voice-memo-button"];
    OWSAssertDebug(icon);
    UIImageView *imageView =
        [[UIImageView alloc] initWithImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    imageView.tintColor = [UIColor ows_destructiveRedColor];
    [self.voiceMemoContentView addSubview:imageView];

    NSMutableAttributedString *cancelString = [NSMutableAttributedString new];
    const CGFloat cancelArrowFontSize = ScaleFromIPhone5To7Plus(18.4, 20.f);
    const CGFloat cancelFontSize = ScaleFromIPhone5To7Plus(14.f, 16.f);
    NSString *arrowHead = (CurrentAppContext().isRTL ? @"\uf105" : @"\uf104");
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
    OWSAssertDebug(whiteIcon);
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
        = (CurrentAppContext().isRTL ? -self.voiceMemoUI.bounds.size.width : self.voiceMemoUI.bounds.size.width);
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

- (void)sendButtonPressed
{
    OWSAssertDebug(self.inputToolbarDelegate);

    [self.inputToolbarDelegate sendButtonPressed];
}

- (void)attachmentButtonPressed
{
    OWSAssertDebug(self.inputToolbarDelegate);

    [self.inputToolbarDelegate attachmentButtonPressed];
}

#pragma mark - ConversationTextViewToolbarDelegate

- (void)textViewDidChange:(UITextView *)textView
{
    OWSAssertDebug(self.inputToolbarDelegate);
    [self ensureShouldShowVoiceMemoButtonAnimated:YES];
    [self updateHeightWithTextView:textView];
}

- (void)updateHeightWithTextView:(UITextView *)textView
{
    // compute new height assuming width is unchanged
    CGSize currentSize = textView.frame.size;
    CGFloat newHeight = [self clampedHeightWithTextView:textView fixedWidth:currentSize.width];

    if (newHeight != self.textViewHeight) {
        self.textViewHeight = newHeight;
        OWSAssertDebug(self.textViewHeightConstraint);
        self.textViewHeightConstraint.constant = newHeight;
        [self invalidateIntrinsicContentSize];
    }
}

- (CGFloat)clampedHeightWithTextView:(UITextView *)textView fixedWidth:(CGFloat)fixedWidth
{
    CGSize fixedWidthSize = CGSizeMake(fixedWidth, CGFLOAT_MAX);
    CGSize contentSize = [textView sizeThatFits:fixedWidthSize];

    return CGFloatClamp(contentSize.height, kMinTextViewHeight, kMaxTextViewHeight);
}

#pragma mark QuotedReplyPreviewViewDelegate

- (void)quotedReplyPreviewDidPressCancel:(QuotedReplyPreview *)preview
{
    self.quotedReply = nil;
}

@end

NS_ASSUME_NONNULL_END
