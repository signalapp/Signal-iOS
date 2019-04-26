//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ConversationInputToolbar.h"
#import "ConversationInputTextView.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "OWSMath.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "ViewControllerUtils.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalMessaging/OWSFormat.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalServiceKit/NSTimer+OWS.h>
#import <SignalServiceKit/TSQuotedMessage.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, VoiceMemoRecordingState){
    VoiceMemoRecordingState_Idle,
    VoiceMemoRecordingState_RecordingHeld,
    VoiceMemoRecordingState_RecordingLocked
};

static void *kConversationInputTextViewObservingContext = &kConversationInputTextViewObservingContext;

const CGFloat kMinTextViewHeight = 36;
const CGFloat kMaxTextViewHeight = 98;

#pragma mark -

@interface InputLinkPreview : NSObject

@property (nonatomic) NSString *previewUrl;
@property (nonatomic, nullable) OWSLinkPreviewDraft *linkPreviewDraft;

@end

#pragma mark -

@implementation InputLinkPreview

@end

#pragma mark -

@interface ConversationInputToolbar () <ConversationTextViewToolbarDelegate,
    QuotedReplyPreviewDelegate,
    LinkPreviewViewDraftDelegate>

@property (nonatomic, readonly) ConversationStyle *conversationStyle;

@property (nonatomic, readonly) ConversationInputTextView *inputTextView;
@property (nonatomic, readonly) UIStackView *hStack;
@property (nonatomic, readonly) UIButton *attachmentButton;
@property (nonatomic, readonly) UIButton *sendButton;
@property (nonatomic, readonly) UIButton *voiceMemoButton;
@property (nonatomic, readonly) UIView *quotedReplyWrapper;
@property (nonatomic, readonly) UIView *linkPreviewWrapper;

@property (nonatomic) CGFloat textViewHeight;
@property (nonatomic, readonly) NSLayoutConstraint *textViewHeightConstraint;

#pragma mark - Voice Memo Recording UI

@property (nonatomic, nullable) UIView *voiceMemoUI;
@property (nonatomic, nullable) VoiceMemoLockView *voiceMemoLockView;
@property (nonatomic, nullable) UIView *voiceMemoContentView;
@property (nonatomic) NSDate *voiceMemoStartTime;
@property (nonatomic, nullable) NSTimer *voiceMemoUpdateTimer;
@property (nonatomic) UIGestureRecognizer *voiceMemoGestureRecognizer;
@property (nonatomic, nullable) UILabel *voiceMemoCancelLabel;
@property (nonatomic, nullable) UIView *voiceMemoRedRecordingCircle;
@property (nonatomic, nullable) UILabel *recordingLabel;
@property (nonatomic, readonly) BOOL isRecordingVoiceMemo;
@property (nonatomic) VoiceMemoRecordingState voiceMemoRecordingState;
@property (nonatomic) CGPoint voiceMemoGestureStartLocation;
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *layoutContraints;
@property (nonatomic) UIEdgeInsets receivedSafeAreaInsets;
@property (nonatomic, nullable) InputLinkPreview *inputLinkPreview;
@property (nonatomic) BOOL wasLinkPreviewCancelled;
@property (nonatomic, nullable, weak) LinkPreviewView *linkPreviewView;

@end

#pragma mark -

@implementation ConversationInputToolbar

- (instancetype)initWithConversationStyle:(ConversationStyle *)conversationStyle
{
    self = [super initWithFrame:CGRectZero];

    _conversationStyle = conversationStyle;
    _receivedSafeAreaInsets = UIEdgeInsetsZero;

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
    self.inputTextView.textViewToolbarDelegate = self;
    self.inputTextView.font = [UIFont ows_dynamicTypeBodyFont];
    self.inputTextView.backgroundColor = Theme.toolbarBackgroundColor;
    [self.inputTextView setContentHuggingLow];
    [self.inputTextView setCompressionResistanceLow];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _inputTextView);

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
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _attachmentButton);

    _sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.sendButton setTitle:MessageStrings.sendButton forState:UIControlStateNormal];
    [self.sendButton setTitleColor:UIColor.ows_signalBlueColor forState:UIControlStateNormal];
    self.sendButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.sendButton.titleLabel.font = [UIFont ows_mediumFontWithSize:17.f];
    self.sendButton.contentEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 4);
    [self.sendButton autoSetDimension:ALDimensionHeight toSize:kMinTextViewHeight];
    [self.sendButton addTarget:self action:@selector(sendButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _sendButton);

    UIImage *voiceMemoIcon = [UIImage imageNamed:@"voice-memo-button"];
    OWSAssertDebug(voiceMemoIcon);
    _voiceMemoButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.voiceMemoButton setImage:[voiceMemoIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                          forState:UIControlStateNormal];
    self.voiceMemoButton.imageView.tintColor = Theme.navbarIconColor;
    [self.voiceMemoButton autoSetDimensionsToSize:CGSizeMake(40, kMinTextViewHeight)];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _voiceMemoButton);

    // We want to be permissive about the voice message gesture, so we hang
    // the long press GR on the button's wrapper, not the button itself.
    UILongPressGestureRecognizer *longPressGestureRecognizer =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPressGestureRecognizer.minimumPressDuration = 0;
    self.voiceMemoGestureRecognizer = longPressGestureRecognizer;
    [self.voiceMemoButton addGestureRecognizer:longPressGestureRecognizer];

    self.userInteractionEnabled = YES;

    _quotedReplyWrapper = [UIView containerView];
    self.quotedReplyWrapper.hidden = YES;
    [self.quotedReplyWrapper setContentHuggingHorizontalLow];
    [self.quotedReplyWrapper setCompressionResistanceHorizontalLow];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _quotedReplyWrapper);

    _linkPreviewWrapper = [UIView containerView];
    self.linkPreviewWrapper.hidden = YES;
    [self.linkPreviewWrapper setContentHuggingHorizontalLow];
    [self.linkPreviewWrapper setCompressionResistanceHorizontalLow];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _linkPreviewWrapper);

    // V Stack
    UIStackView *vStack = [[UIStackView alloc]
        initWithArrangedSubviews:@[ self.quotedReplyWrapper, self.linkPreviewWrapper, self.inputTextView ]];
    vStack.axis = UILayoutConstraintAxisVertical;
    [vStack setContentHuggingHorizontalLow];
    [vStack setCompressionResistanceHorizontalLow];

    for (UIView *button in @[ self.attachmentButton, self.voiceMemoButton, self.sendButton ]) {
        [button setContentHuggingHorizontalHigh];
        [button setCompressionResistanceHorizontalHigh];
    }

    // V Stack Wrapper
    const CGFloat vStackRounding = 18.f;
    UIView *vStackWrapper = [UIView containerView];
    vStackWrapper.layer.cornerRadius = vStackRounding;
    vStackWrapper.clipsToBounds = YES;
    [vStackWrapper addSubview:vStack];
    [vStack ows_autoPinToSuperviewEdges];
    [vStackWrapper setContentHuggingHorizontalLow];
    [vStackWrapper setCompressionResistanceHorizontalLow];

    // H Stack
    _hStack = [[UIStackView alloc]
        initWithArrangedSubviews:@[ self.attachmentButton, vStackWrapper, self.voiceMemoButton, self.sendButton ]];
    self.hStack.axis = UILayoutConstraintAxisHorizontal;
    self.hStack.layoutMarginsRelativeArrangement = YES;
    self.hStack.layoutMargins = UIEdgeInsetsMake(6, 6, 6, 6);
    self.hStack.alignment = UIStackViewAlignmentBottom;
    self.hStack.spacing = 8;

    [self addSubview:self.hStack];
    [self.hStack autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.hStack autoPinEdgeToSuperviewSafeArea:ALEdgeBottom];
    [self.hStack setContentHuggingHorizontalLow];
    [self.hStack setCompressionResistanceHorizontalLow];

    // See comments on updateContentLayout:.
    if (@available(iOS 11, *)) {
        vStack.insetsLayoutMarginsFromSafeArea = NO;
        vStackWrapper.insetsLayoutMarginsFromSafeArea = NO;
        self.hStack.insetsLayoutMarginsFromSafeArea = NO;
        self.insetsLayoutMarginsFromSafeArea = NO;
    }
    vStack.preservesSuperviewLayoutMargins = NO;
    vStackWrapper.preservesSuperviewLayoutMargins = NO;
    self.hStack.preservesSuperviewLayoutMargins = NO;
    self.preservesSuperviewLayoutMargins = NO;

    // Border
    //
    // The border must reside _outside_ of vStackWrapper so
    // that it doesn't run afoul of its clipping, so we can't
    // use addBorderViewWithColor.
    UIView *borderView = [UIView new];
    borderView.userInteractionEnabled = NO;
    borderView.backgroundColor = UIColor.clearColor;
    borderView.opaque = NO;
    borderView.layer.borderColor = Theme.secondaryColor.CGColor;
    borderView.layer.borderWidth = CGHairlineWidth();
    borderView.layer.cornerRadius = vStackRounding;
    [self addSubview:borderView];
    [borderView autoPinToEdgesOfView:vStackWrapper];
    [borderView setCompressionResistanceLow];
    [borderView setContentHuggingLow];

    [self ensureShouldShowVoiceMemoButtonAnimated:NO doLayout:NO];
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

    // It's important that we set the textViewHeight before
    // doing any animation in `ensureShouldShowVoiceMemoButtonAnimated`
    // Otherwise, the resultant keyboard frame posted in `keyboardWillChangeFrame`
    // could reflect the inputTextView height *before* the new text was set.
    //
    // This bug was surfaced to the user as:
    //  - have a quoted reply draft in the input toolbar
    //  - type a multiline message
    //  - hit send
    //  - quoted reply preview and message text is cleared
    //  - input toolbar is shrunk to it's expected empty-text height
    //  - *but* the conversation's bottom content inset was too large. Specifically, it was
    //    still sized as if the input textview was multiple lines.
    // Presumably this bug only surfaced when an animation coincides with more complicated layout
    // changes (in this case while simultaneous with removing quoted reply subviews, hiding the
    // wrapper view *and* changing the height of the input textView
    [self ensureTextViewHeight];
    [self updateInputLinkPreview];

    [self ensureShouldShowVoiceMemoButtonAnimated:isAnimated doLayout:YES];
}

- (void)ensureTextViewHeight
{
    [self updateHeightWithTextView:self.inputTextView];
}

- (void)clearTextMessageAnimated:(BOOL)isAnimated
{
    [self setMessageText:nil animated:isAnimated];
    [self.inputTextView.undoManager removeAllActions];
    self.wasLinkPreviewCancelled = NO;
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

    [self clearQuotedMessagePreview];

    _quotedReply = quotedReply;

    if (!quotedReply) {
        return;
    }

    QuotedReplyPreview *quotedMessagePreview =
        [[QuotedReplyPreview alloc] initWithQuotedReply:quotedReply conversationStyle:self.conversationStyle];
    quotedMessagePreview.delegate = self;
    [quotedMessagePreview setContentHuggingHorizontalLow];
    [quotedMessagePreview setCompressionResistanceHorizontalLow];

    self.quotedReplyWrapper.hidden = NO;
    self.quotedReplyWrapper.layoutMargins = UIEdgeInsetsZero;
    [self.quotedReplyWrapper addSubview:quotedMessagePreview];
    [quotedMessagePreview ows_autoPinToSuperviewMargins];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, quotedMessagePreview);

    self.linkPreviewView.hasAsymmetricalRounding = !self.quotedReply;
}

- (CGFloat)quotedMessageTopMargin
{
    return 5.f;
}

- (void)clearQuotedMessagePreview
{
    self.quotedReplyWrapper.hidden = YES;
    for (UIView *subview in self.quotedReplyWrapper.subviews) {
        [subview removeFromSuperview];
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

- (void)ensureShouldShowVoiceMemoButtonAnimated:(BOOL)isAnimated doLayout:(BOOL)doLayout
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
        if (doLayout) {
            [self layoutIfNeeded];
        }
    };

    if (isAnimated) {
        [UIView animateWithDuration:0.1 animations:updateBlock];
    } else {
        updateBlock();
    }
}

// iOS doesn't always update the safeAreaInsets correctly & in a timely
// way for the inputAccessoryView after a orientation change.  The best
// workaround appears to be to use the safeAreaInsets from
// ConversationViewController's view.  ConversationViewController updates
// this input toolbar using updateLayoutWithIsLandscape:.
- (void)updateContentLayout
{
    if (self.layoutContraints) {
        [NSLayoutConstraint deactivateConstraints:self.layoutContraints];
    }

    self.layoutContraints = @[
        [self.hStack autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:self.receivedSafeAreaInsets.left],
        [self.hStack autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:self.receivedSafeAreaInsets.right],
    ];
}

- (void)updateLayoutWithSafeAreaInsets:(UIEdgeInsets)safeAreaInsets
{
    BOOL didChange = !UIEdgeInsetsEqualToEdgeInsets(self.receivedSafeAreaInsets, safeAreaInsets);
    BOOL hasLayout = self.layoutContraints != nil;

    self.receivedSafeAreaInsets = safeAreaInsets;

    if (didChange || !hasLayout) {
        [self updateContentLayout];
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
                self.voiceMemoRecordingState = VoiceMemoRecordingState_Idle;
                [self.inputToolbarDelegate voiceMemoGestureDidCancel];
            }
            break;
        case UIGestureRecognizerStateBegan:
            switch (self.voiceMemoRecordingState) {
                case VoiceMemoRecordingState_Idle:
                    break;
                case VoiceMemoRecordingState_RecordingHeld:
                    OWSFailDebug(@"while recording held, shouldn't be possible to restart gesture.");
                    [self.inputToolbarDelegate voiceMemoGestureDidCancel];
                    break;
                case VoiceMemoRecordingState_RecordingLocked:
                    OWSFailDebug(@"once locked, shouldn't be possible to interact with gesture.");
                    [self.inputToolbarDelegate voiceMemoGestureDidCancel];
                    break;
            }
            // Start voice message.
            self.voiceMemoRecordingState = VoiceMemoRecordingState_RecordingHeld;
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
                CGFloat xOffset = fabs(self.voiceMemoGestureStartLocation.x - location.x);
                CGFloat yOffset = fabs(self.voiceMemoGestureStartLocation.y - location.y);

                // require a certain threshold before we consider the user to be
                // interacting with the lock ui, otherwise there's perceptible wobble
                // of the lock slider even when the user isn't intended to interact with it.
                const CGFloat kLockThresholdPoints = 20.f;
                const CGFloat kLockOffsetPoints = 80.f;
                CGFloat yOffsetBeyondThreshold = MAX(yOffset - kLockThresholdPoints, 0);
                CGFloat lockAlpha = yOffsetBeyondThreshold / kLockOffsetPoints;
                BOOL isLocked = lockAlpha >= 1.f;
                if (isLocked) {
                    switch (self.voiceMemoRecordingState) {
                        case VoiceMemoRecordingState_RecordingHeld:
                            self.voiceMemoRecordingState = VoiceMemoRecordingState_RecordingLocked;
                            [self.inputToolbarDelegate voiceMemoGestureDidLock];
                            [self.inputToolbarDelegate voiceMemoGestureDidUpdateCancelWithRatioComplete:0];
                            break;
                        case VoiceMemoRecordingState_RecordingLocked:
                            // already locked
                            break;
                        case VoiceMemoRecordingState_Idle:
                            OWSFailDebug(@"failure: unexpeceted idle state");
                            [self.inputToolbarDelegate voiceMemoGestureDidCancel];
                            break;
                    }
                } else {
                    [self.voiceMemoLockView updateWithRatioComplete:lockAlpha];

                    // The lower this value, the easier it is to cancel by accident.
                    // The higher this value, the harder it is to cancel.
                    const CGFloat kCancelOffsetPoints = 100.f;
                    CGFloat cancelAlpha = xOffset / kCancelOffsetPoints;
                    BOOL isCancelled = cancelAlpha >= 1.f;
                    if (isCancelled) {
                        self.voiceMemoRecordingState = VoiceMemoRecordingState_Idle;
                        [self.inputToolbarDelegate voiceMemoGestureDidCancel];
                        break;
                    } else {
                        [self.inputToolbarDelegate voiceMemoGestureDidUpdateCancelWithRatioComplete:cancelAlpha];
                    }
                }
            }
            break;
        case UIGestureRecognizerStateEnded:
            switch (self.voiceMemoRecordingState) {
                case VoiceMemoRecordingState_Idle:
                    break;
                case VoiceMemoRecordingState_RecordingHeld:
                    // End voice message.
                    self.voiceMemoRecordingState = VoiceMemoRecordingState_Idle;
                    [self.inputToolbarDelegate voiceMemoGestureDidComplete];
                    break;
                case VoiceMemoRecordingState_RecordingLocked:
                    // Continue recording.
                    break;
            }
            break;
    }
}

#pragma mark - Voice Memo

- (BOOL)isRecordingVoiceMemo
{
    switch (self.voiceMemoRecordingState) {
        case VoiceMemoRecordingState_Idle:
            return NO;
        case VoiceMemoRecordingState_RecordingHeld:
        case VoiceMemoRecordingState_RecordingLocked:
            return YES;
    }
}

- (void)showVoiceMemoUI
{
    OWSAssertIsOnMainThread();

    self.voiceMemoStartTime = [NSDate date];

    [self.voiceMemoUI removeFromSuperview];
    [self.voiceMemoLockView removeFromSuperview];

    self.voiceMemoUI = [UIView new];
    self.voiceMemoUI.backgroundColor = Theme.toolbarBackgroundColor;
    [self addSubview:self.voiceMemoUI];
    [self.voiceMemoUI autoPinEdgesToSuperviewEdges];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _voiceMemoUI);

    self.voiceMemoContentView = [UIView new];
    [self.voiceMemoUI addSubview:self.voiceMemoContentView];
    [self.voiceMemoContentView ows_autoPinToSuperviewEdges];

    self.recordingLabel = [UILabel new];
    self.recordingLabel.textColor = [UIColor ows_destructiveRedColor];
    self.recordingLabel.font = [UIFont ows_mediumFontWithSize:14.f];
    [self.voiceMemoContentView addSubview:self.recordingLabel];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _recordingLabel);

    VoiceMemoLockView *voiceMemoLockView = [VoiceMemoLockView new];
    self.voiceMemoLockView = voiceMemoLockView;
    [self addSubview:voiceMemoLockView];
    [voiceMemoLockView autoPinTrailingToSuperviewMargin];
    [voiceMemoLockView autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:self.voiceMemoContentView];
    [voiceMemoLockView setCompressionResistanceHigh];

    [self updateVoiceMemo];

    UIImage *icon = [UIImage imageNamed:@"voice-memo-button"];
    OWSAssertDebug(icon);
    UIImageView *imageView =
        [[UIImageView alloc] initWithImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    imageView.tintColor = [UIColor ows_destructiveRedColor];
    [imageView setContentHuggingHigh];
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
    self.voiceMemoCancelLabel = cancelLabel;
    cancelLabel.attributedText = cancelString;
    [self.voiceMemoContentView addSubview:cancelLabel];

    const CGFloat kRedCircleSize = 100.f;
    UIView *redCircleView = [UIView new];
    self.voiceMemoRedRecordingCircle = redCircleView;
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
    [self.voiceMemoUI layoutIfNeeded];

    // Slide in the "slide to cancel" label.
    CGRect cancelLabelStartFrame = cancelLabel.frame;
    CGRect cancelLabelEndFrame = cancelLabel.frame;
    cancelLabelStartFrame.origin.x
        = (CurrentAppContext().isRTL ? -self.voiceMemoUI.bounds.size.width : self.voiceMemoUI.bounds.size.width);
    cancelLabel.frame = cancelLabelStartFrame;

    voiceMemoLockView.transform = CGAffineTransformMakeScale(0.0, 0.0);
    [voiceMemoLockView layoutIfNeeded];
    [UIView animateWithDuration:0.2f
                          delay:1.f
                        options:0
                     animations:^{
                         voiceMemoLockView.transform = CGAffineTransformIdentity;
                     }
                     completion:nil];

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

    self.voiceMemoRecordingState = VoiceMemoRecordingState_Idle;

    UIView *oldVoiceMemoUI = self.voiceMemoUI;
    UIView *oldVoiceMemoLockView = self.voiceMemoLockView;

    self.voiceMemoUI = nil;
    self.voiceMemoCancelLabel = nil;
    self.voiceMemoRedRecordingCircle = nil;
    self.voiceMemoContentView = nil;
    self.voiceMemoLockView = nil;
    self.recordingLabel = nil;

    [self.voiceMemoUpdateTimer invalidate];
    self.voiceMemoUpdateTimer = nil;

    [oldVoiceMemoUI.layer removeAllAnimations];

    if (animated) {
        [UIView animateWithDuration:0.35f
            animations:^{
                oldVoiceMemoUI.layer.opacity = 0.f;
                oldVoiceMemoLockView.layer.opacity = 0.f;
            }
            completion:^(BOOL finished) {
                [oldVoiceMemoUI removeFromSuperview];
                [oldVoiceMemoLockView removeFromSuperview];
            }];
    } else {
        [oldVoiceMemoUI removeFromSuperview];
        [oldVoiceMemoLockView removeFromSuperview];
    }
}

- (void)lockVoiceMemoUI
{
    __weak __typeof(self) weakSelf = self;

    UIButton *sendVoiceMemoButton = [[OWSButton alloc] initWithBlock:^{
        [weakSelf.inputToolbarDelegate voiceMemoGestureDidComplete];
    }];
    [sendVoiceMemoButton setTitle:MessageStrings.sendButton forState:UIControlStateNormal];
    [sendVoiceMemoButton setTitleColor:UIColor.ows_signalBlueColor forState:UIControlStateNormal];
    sendVoiceMemoButton.alpha = 0;
    [self.voiceMemoContentView addSubview:sendVoiceMemoButton];
    [sendVoiceMemoButton autoPinEdgeToSuperviewMargin:ALEdgeTrailing withInset:10.f];
    [sendVoiceMemoButton autoVCenterInSuperview];
    [sendVoiceMemoButton setCompressionResistanceHigh];
    [sendVoiceMemoButton setContentHuggingHigh];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, sendVoiceMemoButton);

    UIButton *cancelButton = [[OWSButton alloc] initWithBlock:^{
        [weakSelf.inputToolbarDelegate voiceMemoGestureDidCancel];
    }];
    [cancelButton setTitle:CommonStrings.cancelButton forState:UIControlStateNormal];
    [cancelButton setTitleColor:UIColor.ows_destructiveRedColor forState:UIControlStateNormal];
    cancelButton.alpha = 0;
    cancelButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, cancelButton);

    [self.voiceMemoContentView addSubview:cancelButton];
    OWSAssert(self.recordingLabel != nil);
    [self.recordingLabel setContentHuggingHigh];

    [NSLayoutConstraint autoSetPriority:UILayoutPriorityDefaultLow
                         forConstraints:^{
                             [cancelButton autoHCenterInSuperview];
                         }];
    [cancelButton autoPinEdge:ALEdgeLeading
                       toEdge:ALEdgeTrailing
                       ofView:self.recordingLabel
                   withOffset:4
                     relation:NSLayoutRelationGreaterThanOrEqual];
    [cancelButton autoPinEdge:ALEdgeTrailing
                       toEdge:ALEdgeLeading
                       ofView:sendVoiceMemoButton
                   withOffset:-4
                     relation:NSLayoutRelationLessThanOrEqual];
    [cancelButton autoVCenterInSuperview];

    [self.voiceMemoContentView layoutIfNeeded];
    [UIView animateWithDuration:0.35
        animations:^{
            self.voiceMemoCancelLabel.alpha = 0;
            self.voiceMemoRedRecordingCircle.alpha = 0;
            self.voiceMemoLockView.transform = CGAffineTransformMakeScale(0, 0);
            cancelButton.alpha = 1.0;
            sendVoiceMemoButton.alpha = 1.0;
        }
        completion:^(BOOL finished) {
            [self.voiceMemoCancelLabel removeFromSuperview];
            [self.voiceMemoRedRecordingCircle removeFromSuperview];
            [self.voiceMemoLockView removeFromSuperview];
        }];
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
        self.voiceMemoRecordingState = VoiceMemoRecordingState_Idle;
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
    [self ensureShouldShowVoiceMemoButtonAnimated:YES doLayout:YES];
    [self updateHeightWithTextView:textView];
    [self updateInputLinkPreview];
}

- (void)textViewDidChangeSelection:(UITextView *)textView
{
    [self updateInputLinkPreview];
}

- (void)updateHeightWithTextView:(UITextView *)textView
{
    // compute new height assuming width is unchanged
    CGSize currentSize = textView.frame.size;

    CGFloat fixedWidth = currentSize.width;
    CGSize contentSize = [textView sizeThatFits:CGSizeMake(fixedWidth, CGFLOAT_MAX)];

    // `textView.contentSize` isn't accurate when restoring a multiline draft, so we compute it here.
    textView.contentSize = contentSize;

    CGFloat newHeight = CGFloatClamp(contentSize.height, kMinTextViewHeight, kMaxTextViewHeight);

    if (newHeight != self.textViewHeight) {
        self.textViewHeight = newHeight;
        OWSAssertDebug(self.textViewHeightConstraint);
        self.textViewHeightConstraint.constant = newHeight;
        [self invalidateIntrinsicContentSize];
    }
}

#pragma mark QuotedReplyPreviewViewDelegate

- (void)quotedReplyPreviewDidPressCancel:(QuotedReplyPreview *)preview
{
    self.quotedReply = nil;
}

#pragma mark - Link Preview

- (void)updateInputLinkPreview
{
    OWSAssertIsOnMainThread();

    NSString *body =
        [[self messageText] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (body.length < 1) {
        [self clearLinkPreviewStateAndView];
        self.wasLinkPreviewCancelled = NO;
        return;
    }

    if (self.wasLinkPreviewCancelled) {
        [self clearLinkPreviewStateAndView];
        return;
    }

    // Don't include link previews for oversize text messages.
    if ([body lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= kOversizeTextMessageSizeThreshold) {
        [self clearLinkPreviewStateAndView];
        return;
    }

    // It's key that we use the *raw/unstripped* text, so we can reconcile cursor position with the
    // selectedRange.
    NSString *_Nullable previewUrl = [OWSLinkPreview previewUrlForRawBodyText:self.inputTextView.text
                                                                selectedRange:self.inputTextView.selectedRange];
    if (previewUrl.length < 1) {
        [self clearLinkPreviewStateAndView];
        return;
    }

    if (self.inputLinkPreview && [self.inputLinkPreview.previewUrl isEqualToString:previewUrl]) {
        // No need to update.
        return;
    }

    InputLinkPreview *inputLinkPreview = [InputLinkPreview new];
    self.inputLinkPreview = inputLinkPreview;
    self.inputLinkPreview.previewUrl = previewUrl;

    [self ensureLinkPreviewViewWithState:[LinkPreviewLoading new]];

    __weak ConversationInputToolbar *weakSelf = self;
    [[OWSLinkPreview tryToBuildPreviewInfoObjcWithPreviewUrl:previewUrl]
            .then(^(OWSLinkPreviewDraft *linkPreviewDraft) {
                ConversationInputToolbar *_Nullable strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }
                if (strongSelf.inputLinkPreview != inputLinkPreview) {
                    // Obsolete callback.
                    return;
                }
                inputLinkPreview.linkPreviewDraft = linkPreviewDraft;
                LinkPreviewDraft *viewState = [[LinkPreviewDraft alloc] initWithLinkPreviewDraft:linkPreviewDraft];
                [strongSelf ensureLinkPreviewViewWithState:viewState];
            })
            .catch(^(id error) {
                // The link preview could not be loaded.
                [weakSelf clearLinkPreviewView];
            }) retainUntilComplete];
}

- (void)ensureLinkPreviewViewWithState:(id<LinkPreviewState>)state
{
    OWSAssertIsOnMainThread();

    [self clearLinkPreviewView];

    LinkPreviewView *linkPreviewView = [[LinkPreviewView alloc] initWithDraftDelegate:self];
    linkPreviewView.state = state;
    linkPreviewView.hasAsymmetricalRounding = !self.quotedReply;
    self.linkPreviewView = linkPreviewView;

    self.linkPreviewWrapper.hidden = NO;
    [self.linkPreviewWrapper addSubview:linkPreviewView];
    [linkPreviewView ows_autoPinToSuperviewMargins];
}

- (void)clearLinkPreviewStateAndView
{
    OWSAssertIsOnMainThread();

    self.inputLinkPreview = nil;
    self.linkPreviewView = nil;

    [self clearLinkPreviewView];
}

- (void)clearLinkPreviewView
{
    OWSAssertIsOnMainThread();

    // Clear old link preview state.
    for (UIView *subview in self.linkPreviewWrapper.subviews) {
        [subview removeFromSuperview];
    }
    self.linkPreviewWrapper.hidden = YES;
}

- (nullable OWSLinkPreviewDraft *)linkPreviewDraft
{
    OWSAssertIsOnMainThread();

    if (!self.inputLinkPreview) {
        return nil;
    }
    if (self.wasLinkPreviewCancelled) {
        return nil;
    }
    return self.inputLinkPreview.linkPreviewDraft;
}

#pragma mark - LinkPreviewViewDraftDelegate

- (BOOL)linkPreviewCanCancel
{
    OWSAssertIsOnMainThread();

    return YES;
}

- (void)linkPreviewDidCancel
{
    OWSAssertIsOnMainThread();

    self.wasLinkPreviewCancelled = YES;

    self.inputLinkPreview = nil;
    [self clearLinkPreviewStateAndView];
}

@end

NS_ASSUME_NONNULL_END
