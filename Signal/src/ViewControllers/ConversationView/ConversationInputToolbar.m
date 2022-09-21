//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import "ConversationInputToolbar.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/SignalCoreKit-Swift.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/NSTimer+OWS.h>
#import <SignalServiceKit/OWSMath.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSQuotedMessage.h>
#import <SignalUI/UIFont+OWS.h>
#import <SignalUI/UIView+SignalUI.h>
#import <SignalUI/ViewControllerUtils.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, VoiceMemoRecordingState) {
    VoiceMemoRecordingState_Idle,
    VoiceMemoRecordingState_RecordingHeld,
    VoiceMemoRecordingState_RecordingLocked,
    VoiceMemoRecordingState_Draft
};

typedef NS_CLOSED_ENUM(NSUInteger, KeyboardType) { KeyboardType_System, KeyboardType_Sticker, KeyboardType_Attachment };

const CGFloat kMinTextViewHeight = 36;
const CGFloat kMinToolbarItemHeight = 44;
const CGFloat kMaxTextViewHeight = 98;
const CGFloat kMaxIPadTextViewHeight = 142;

#pragma mark -

@interface InputLinkPreview : NSObject

@property (nonatomic) NSURL *previewUrl;
@property (nonatomic, nullable) OWSLinkPreviewDraft *linkPreviewDraft;

@end

#pragma mark -

@implementation InputLinkPreview

@end

#pragma mark -


@interface ConversationInputToolbar () <ConversationTextViewToolbarDelegate,
    QuotedReplyPreviewDelegate,
    LinkPreviewViewDraftDelegate,
    StickerKeyboardDelegate,
    AttachmentKeyboardDelegate>

@property (nonatomic, readonly) ConversationStyle *conversationStyle;
@property (nonatomic, readonly) CVMediaCache *mediaCache;

@property (nonatomic, weak) id<ConversationInputToolbarDelegate> inputToolbarDelegate;

@property (nonatomic, readonly) ConversationInputTextView *inputTextView;
@property (nonatomic, readonly) UIButton *cameraButton;
@property (nonatomic, readonly) LottieToggleButton *attachmentButton;
@property (nonatomic, readonly) UIButton *sendButton;
@property (nonatomic, readonly) UIButton *voiceMemoButton;
@property (nonatomic, readonly) UIButton *stickerButton;
@property (nonatomic, readonly) UIView *quotedReplyWrapper;
@property (nonatomic, readonly) UIView *linkPreviewWrapper;
@property (nonatomic, readonly) StickerHorizontalListView *suggestedStickerView;
@property (nonatomic) NSArray<StickerInfo *> *suggestedStickerInfos;
@property (nonatomic, readonly) StickerViewCache *suggestedStickerViewCache;
@property (nonatomic, readonly) UIStackView *outerStack;
@property (nonatomic, readonly) UIStackView *mediaAndSendStack;

@property (nonatomic) CGFloat textViewHeight;
@property (nonatomic, readonly) NSLayoutConstraint *textViewHeightConstraint;

#pragma mark - Voice Memo Recording UI

@property (nonatomic, nullable) VoiceMemoLockView *voiceMemoLockView;
@property (nonatomic, readonly) UIView *voiceMemoContentViewLeftSpacer;
@property (nonatomic, readonly) UIView *voiceMemoContentViewRightSpacer;
@property (nonatomic, readonly) UIView *voiceMemoContentView;
@property (nonatomic) NSDate *voiceMemoStartTime;
@property (nonatomic, nullable) NSTimer *voiceMemoUpdateTimer;
@property (nonatomic) UIGestureRecognizer *voiceMemoGestureRecognizer;
@property (nonatomic, nullable) UILabel *voiceMemoCancelLabel;
@property (nonatomic, nullable) UIView *voiceMemoRedRecordingCircle;
@property (nonatomic, nullable) UILabel *recordingLabel;
@property (nonatomic) BOOL isShowingVoiceMemoUI;
@property (nonatomic) VoiceMemoRecordingState voiceMemoRecordingState;
@property (nonatomic) CGPoint voiceMemoGestureStartLocation;
@property (nonatomic, nullable, weak) UIView *voiceMemoTooltip;
@property (nonatomic, nullable) VoiceMessageModel *voiceMemoDraft;
@property (nonatomic, nullable) NSArray<NSLayoutConstraint *> *layoutContraints;
@property (nonatomic) UIEdgeInsets receivedSafeAreaInsets;
@property (nonatomic, nullable) InputLinkPreview *inputLinkPreview;
@property (nonatomic) BOOL wasLinkPreviewCancelled;
@property (nonatomic, nullable, weak) LinkPreviewView *linkPreviewView;
@property (nonatomic) BOOL isConfigurationComplete;

#pragma mark - Keyboards

@property (nonatomic) KeyboardType desiredKeyboardType;
@property (nonatomic, readonly) StickerKeyboard *stickerKeyboard;
@property (nonatomic, readonly) AttachmentKeyboard *attachmentKeyboard;
@property (nonatomic) BOOL hasMeasuredKeyboardHeight;

#pragma mark - Quoted replies

@property (nonatomic, assign, readwrite) BOOL isAnimatingQuotedReply;

@end

#pragma mark -

@implementation ConversationInputToolbar

@synthesize stickerKeyboard = _stickerKeyboard;
@synthesize attachmentKeyboard = _attachmentKeyboard;

- (instancetype)initWithConversationStyle:(ConversationStyle *)conversationStyle
                               mediaCache:(CVMediaCache *)mediaCache
                             messageDraft:(nullable MessageBody *)messageDraft
                              quotedReply:(nullable OWSQuotedReplyModel *)quotedReply
                     inputToolbarDelegate:(id<ConversationInputToolbarDelegate>)inputToolbarDelegate
                    inputTextViewDelegate:(id<ConversationInputTextViewDelegate>)inputTextViewDelegate
                          mentionDelegate:(id<MentionTextViewDelegate>)mentionDelegate
{
    self = [super initWithFrame:CGRectZero];

    _conversationStyle = conversationStyle;
    _mediaCache = mediaCache;
    _receivedSafeAreaInsets = UIEdgeInsetsZero;
    _suggestedStickerViewCache = [[StickerViewCache alloc] initWithMaxSize:12];

    self.inputToolbarDelegate = inputToolbarDelegate;

    if (self) {
        [self createContentsWithMessageDraft:messageDraft
                                 quotedReply:quotedReply
                       inputTextViewDelegate:inputTextViewDelegate
                             mentionDelegate:mentionDelegate];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardFrameDidChange:)
                                                 name:UIKeyboardDidChangeFrameNotification
                                               object:nil];

    return self;
}

#pragma mark -

- (CGSize)intrinsicContentSize
{
    // Since we have `self.autoresizingMask = UIViewAutoresizingFlexibleHeight`, we must specify
    // an intrinsicContentSize. Specifying CGSize.zero causes the height to be determined by autolayout.
    return CGSizeZero;
}

- (void)createContentsWithMessageDraft:(nullable MessageBody *)messageDraft
                           quotedReply:(nullable OWSQuotedReplyModel *)quotedReply
                 inputTextViewDelegate:(id<ConversationInputTextViewDelegate>)inputTextViewDelegate
                       mentionDelegate:(id<MentionTextViewDelegate>)mentionDelegate
{
    // The input toolbar should *always* be laid out left-to-right, even when using
    // a right-to-left language. The convention for messaging apps is for the send
    // button to always be to the right of the input field, even in RTL layouts.
    // This means, in most places you'll want to pin deliberately to left/right
    // instead of leading/trailing. You'll also want to the semanticContentAttribute
    // to ensure horizontal stack views layout left-to-right.

    self.layoutMargins = UIEdgeInsetsZero;

    // When presenting or dismissing the keyboard, there may be a slight
    // gap between the keyboard and the bottom of the input bar during
    // the animation. Extend the background below the toolbar's bounds
    // by this much to mask that extra space.
    CGFloat backgroundExtension = 500;

    if (UIAccessibilityIsReduceTransparencyEnabled()) {
        self.backgroundColor = Theme.toolbarBackgroundColor;

        UIView *extendedBackground = [UIView new];
        extendedBackground.backgroundColor = Theme.toolbarBackgroundColor;
        [self addSubview:extendedBackground];
        [extendedBackground autoPinWidthToSuperview];
        [extendedBackground autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self];
        [extendedBackground autoSetDimension:ALDimensionHeight toSize:backgroundExtension];
    } else {
        CGFloat alpha = OWSNavigationBar.backgroundBlurMutingFactor;
        self.backgroundColor = [Theme.toolbarBackgroundColor colorWithAlphaComponent:alpha];

        UIVisualEffectView *blurEffectView = [[UIVisualEffectView alloc] initWithEffect:Theme.barBlurEffect];
        blurEffectView.layer.zPosition = -1;
        [self addSubview:blurEffectView];
        [blurEffectView autoPinWidthToSuperview];
        [blurEffectView autoPinEdgeToSuperviewEdge:ALEdgeTop];
        [blurEffectView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:-backgroundExtension];
    }

    self.autoresizingMask = UIViewAutoresizingFlexibleHeight;

    _inputTextView = [ConversationInputTextView new];
    self.inputTextView.textViewToolbarDelegate = self;
    self.inputTextView.font = [UIFont ows_dynamicTypeBodyFont];
    self.inputTextView.backgroundColor = Theme.conversationInputBackgroundColor;
    [self.inputTextView setContentHuggingLow];
    [self.inputTextView setCompressionResistanceLow];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _inputTextView);

    // NOTE: Don't set inputTextViewDelegate until configuration is complete.
    self.inputTextView.mentionDelegate = mentionDelegate;

    // NOTE: Don't set inputTextViewDelegate until configuration is complete.
    self.inputTextView.inputTextViewDelegate = inputTextViewDelegate;

    _textViewHeightConstraint = [self.inputTextView autoSetDimension:ALDimensionHeight toSize:kMinTextViewHeight];

    _cameraButton = [[UIButton alloc] init];
    self.cameraButton.accessibilityLabel
        = NSLocalizedString(@"CAMERA_BUTTON_LABEL", @"Accessibility label for camera button.");
    self.cameraButton.accessibilityHint = NSLocalizedString(
        @"CAMERA_BUTTON_HINT", @"Accessibility hint describing what you can do with the camera button");
    [self.cameraButton addTarget:self
                          action:@selector(cameraButtonPressed)
                forControlEvents:UIControlEventTouchUpInside];
    UIImage *cameraIcon = [Theme iconImage:ThemeIconCameraButton];
    [self.cameraButton setTemplateImage:cameraIcon tintColor:Theme.primaryIconColor];
    [self.cameraButton autoSetDimensionsToSize:CGSizeMake(40, kMinToolbarItemHeight)];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _cameraButton);

    _attachmentButton = [[LottieToggleButton alloc] init];
    self.attachmentButton.accessibilityLabel
        = NSLocalizedString(@"ATTACHMENT_LABEL", @"Accessibility label for attaching photos");
    self.attachmentButton.accessibilityHint = NSLocalizedString(
        @"ATTACHMENT_HINT", @"Accessibility hint describing what you can do with the attachment button");
    [self.attachmentButton addTarget:self
                              action:@selector(attachmentButtonPressed)
                    forControlEvents:UIControlEventTouchUpInside];
    self.attachmentButton.animationName = Theme.isDarkThemeEnabled ? @"attachment_dark" : @"attachment_light";
    self.attachmentButton.animationSize = CGSizeMake(28, 28);
    [self.attachmentButton autoSetDimensionsToSize:CGSizeMake(55, kMinToolbarItemHeight)];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _attachmentButton);

    _sendButton = [[UIButton alloc] init];
    self.sendButton.accessibilityLabel = MessageStrings.sendButton;
    [self.sendButton addTarget:self action:@selector(sendButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.sendButton setTemplateImageName:@"send-solid-24" tintColor:UIColor.ows_accentBlueColor];
    [self.sendButton autoSetDimensionsToSize:CGSizeMake(50, kMinToolbarItemHeight)];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _sendButton);

    _voiceMemoButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.voiceMemoButton.accessibilityLabel = NSLocalizedString(@"INPUT_TOOLBAR_VOICE_MEMO_BUTTON_ACCESSIBILITY_LABEL",
        @"accessibility label for the button which records voice memos");
    self.voiceMemoButton.accessibilityHint = NSLocalizedString(@"INPUT_TOOLBAR_VOICE_MEMO_BUTTON_ACCESSIBILITY_HINT",
        @"accessibility hint for the button which records voice memos");
    UIImage *micIcon = [Theme iconImage:ThemeIconMicButton];
    [self.voiceMemoButton setTemplateImage:micIcon tintColor:Theme.primaryIconColor];
    [self.voiceMemoButton autoSetDimensionsToSize:CGSizeMake(40, kMinToolbarItemHeight)];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _voiceMemoButton);

    _stickerButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.stickerButton.accessibilityLabel = NSLocalizedString(@"INPUT_TOOLBAR_STICKER_BUTTON_ACCESSIBILITY_LABEL",
        @"accessibility label for the button which shows the sticker picker");
    UIImage *stickerIcon = [Theme iconImage:ThemeIconStickerButton];
    [self.stickerButton setTemplateImage:stickerIcon tintColor:Theme.primaryIconColor];
    [self.stickerButton addTarget:self
                           action:@selector(stickerButtonPressed)
                 forControlEvents:UIControlEventTouchUpInside];
    [self.stickerButton autoSetDimensionsToSize:CGSizeMake(40, kMinToolbarItemHeight)];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _stickerButton);

    // We want to be permissive about the voice message gesture, so we hang
    // the long press GR on the button's wrapper, not the button itself.
    UILongPressGestureRecognizer *longPressGestureRecognizer =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPressGestureRecognizer.minimumPressDuration = 0;
    self.voiceMemoGestureRecognizer = longPressGestureRecognizer;
    [self.voiceMemoButton addGestureRecognizer:longPressGestureRecognizer];

    self.userInteractionEnabled = YES;

    if (SSKDebugFlags.internalLogging) {
        OWSLogInfo(@"");
    }

    _quotedReplyWrapper = [UIView containerView];
    self.quotedReplyWrapper.hidden = quotedReply == nil;
    [self.quotedReplyWrapper setContentHuggingHorizontalLow];
    [self.quotedReplyWrapper setCompressionResistanceHorizontalLow];
    self.quotedReplyWrapper.backgroundColor = Theme.conversationInputBackgroundColor;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _quotedReplyWrapper);
    self.quotedReply = quotedReply;

    _linkPreviewWrapper = [UIView containerView];
    self.linkPreviewWrapper.hidden = YES;
    [self.linkPreviewWrapper setContentHuggingHorizontalLow];
    [self.linkPreviewWrapper setCompressionResistanceHorizontalLow];
    self.linkPreviewWrapper.backgroundColor = Theme.conversationInputBackgroundColor;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _linkPreviewWrapper);

    _voiceMemoContentView = [UIView containerView];
    self.voiceMemoContentView.hidden = YES;
    [self.voiceMemoContentView setContentHuggingHorizontalLow];
    [self.voiceMemoContentView setCompressionResistanceHorizontalLow];
    self.voiceMemoContentView.backgroundColor = Theme.conversationInputBackgroundColor;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _voiceMemoContentView);

    _voiceMemoContentViewLeftSpacer = [UIView containerView];
    self.voiceMemoContentViewLeftSpacer.hidden = YES;
    [self.voiceMemoContentViewLeftSpacer autoSetDimension:ALDimensionHeight toSize:kMinToolbarItemHeight];
    [self.voiceMemoContentViewLeftSpacer autoSetDimension:ALDimensionWidth toSize:16];
    _voiceMemoContentViewRightSpacer = [UIView containerView];
    self.voiceMemoContentViewRightSpacer.hidden = YES;
    [self.voiceMemoContentViewRightSpacer autoSetDimension:ALDimensionHeight toSize:kMinToolbarItemHeight];
    [self.voiceMemoContentViewRightSpacer autoSetDimension:ALDimensionWidth toSize:16];

    // V Stack
    UIStackView *vStack = [[UIStackView alloc]
        initWithArrangedSubviews:@[ self.quotedReplyWrapper, self.linkPreviewWrapper, self.inputTextView ]];
    vStack.axis = UILayoutConstraintAxisVertical;
    vStack.alignment = UIStackViewAlignmentFill;
    [vStack setContentHuggingHorizontalLow];
    [vStack setCompressionResistanceHorizontalLow];

    [vStack addSubview:self.voiceMemoContentView];
    [self.voiceMemoContentView autoPinToEdgesOfView:self.inputTextView];

    for (UIView *button in
        @[ self.cameraButton, self.attachmentButton, self.stickerButton, self.voiceMemoButton, self.sendButton ]) {
        [button setContentHuggingHorizontalHigh];
        [button setCompressionResistanceHorizontalHigh];
    }

    // V Stack Wrapper
    const CGFloat vStackRounding = 18.f;
    UIView *vStackRoundingView = [UIView containerView];
    vStackRoundingView.layer.cornerRadius = vStackRounding;
    vStackRoundingView.clipsToBounds = YES;
    [vStackRoundingView addSubview:vStack];
    [vStack autoPinEdgesToSuperviewEdges];
    [vStackRoundingView setContentHuggingHorizontalLow];
    [vStackRoundingView setCompressionResistanceHorizontalLow];

    UIView *vStackRoundingOffsetView = [UIView containerView];
    [vStackRoundingOffsetView addSubview:vStackRoundingView];
    CGFloat textViewCenterInset = (kMinToolbarItemHeight - kMinTextViewHeight) / 2;
    [vStackRoundingView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:textViewCenterInset];
    [vStackRoundingView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [vStackRoundingView autoPinEdgeToSuperviewEdge:ALEdgeLeft];
    [vStackRoundingView autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:8];

    // Media Stack
    UIStackView *mediaAndSendStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.voiceMemoContentViewRightSpacer,
        self.sendButton,
        self.cameraButton,
        self.voiceMemoButton,
    ]];
    _mediaAndSendStack = mediaAndSendStack;
    mediaAndSendStack.axis = UILayoutConstraintAxisHorizontal;
    mediaAndSendStack.alignment = UIStackViewAlignmentCenter;
    mediaAndSendStack.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    [mediaAndSendStack setContentHuggingHorizontalHigh];
    [mediaAndSendStack setCompressionResistanceHorizontalHigh];

    // H Stack
    UIStackView *hStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.voiceMemoContentViewLeftSpacer,
        self.attachmentButton,
        vStackRoundingOffsetView,
        mediaAndSendStack,
    ]];
    hStack.axis = UILayoutConstraintAxisHorizontal;
    hStack.alignment = UIStackViewAlignmentBottom;
    hStack.layoutMarginsRelativeArrangement = YES;
    hStack.layoutMargins = UIEdgeInsetsMake(6, 6, 6, 6);
    hStack.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;

    // Suggested Stickers
    const CGFloat suggestedStickerSize = 48;
    const CGFloat suggestedStickerSpacing = 12;
    _suggestedStickerView = [[StickerHorizontalListView alloc] initWithCellSize:suggestedStickerSize
                                                                      cellInset:0
                                                                        spacing:suggestedStickerSpacing];
    self.suggestedStickerView.backgroundColor = Theme.conversationButtonBackgroundColor;
    const UIEdgeInsets stickerListContentInset
        = UIEdgeInsetsMake(suggestedStickerSpacing, 24, suggestedStickerSpacing, 24);
    self.suggestedStickerView.contentInset = stickerListContentInset;
    self.suggestedStickerView.isHiddenInStackView = YES;
    [self.suggestedStickerView
        autoSetDimension:ALDimensionHeight
                  toSize:suggestedStickerSize + stickerListContentInset.bottom + stickerListContentInset.top];

    // "Outer" Stack
    _outerStack = [[UIStackView alloc] initWithArrangedSubviews:@[ self.suggestedStickerView, hStack ]];
    self.outerStack.axis = UILayoutConstraintAxisVertical;
    self.outerStack.alignment = UIStackViewAlignmentFill;
    [self addSubview:self.outerStack];
    [self.outerStack autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.outerStack autoPinEdgeToSuperviewSafeArea:ALEdgeBottom];

    // See comments on updateContentLayout:.
    self.suggestedStickerView.insetsLayoutMarginsFromSafeArea = NO;
    vStack.insetsLayoutMarginsFromSafeArea = NO;
    vStackRoundingOffsetView.insetsLayoutMarginsFromSafeArea = NO;
    hStack.insetsLayoutMarginsFromSafeArea = NO;
    self.outerStack.insetsLayoutMarginsFromSafeArea = NO;
    self.insetsLayoutMarginsFromSafeArea = NO;

    self.suggestedStickerView.preservesSuperviewLayoutMargins = NO;
    vStack.preservesSuperviewLayoutMargins = NO;
    vStackRoundingOffsetView.preservesSuperviewLayoutMargins = NO;
    hStack.preservesSuperviewLayoutMargins = NO;
    self.outerStack.preservesSuperviewLayoutMargins = NO;
    self.preservesSuperviewLayoutMargins = NO;

    // Input buttons
    [self addSubview:self.stickerButton];
    [self.stickerButton autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.inputTextView];
    [self.stickerButton autoPinEdge:ALEdgeTrailing toEdge:ALEdgeTrailing ofView:vStackRoundingView withOffset:-4];

    [self setMessageBody:messageDraft animated:NO doLayout:NO];

    self.isConfigurationComplete = YES;
}

// This getter can be used to access stickerKeyboard without triggering lazy creation.
- (nullable StickerKeyboard *)stickerKeyboardIfSet
{
    return _stickerKeyboard;
}

- (StickerKeyboard *)stickerKeyboard
{
    // Lazy-create. This keyboard is expensive to build and can
    // delay CVC presentation.
    if (_stickerKeyboard == nil) {
        StickerKeyboard *stickerKeyboard = [StickerKeyboard new];
        _stickerKeyboard = stickerKeyboard;
        stickerKeyboard.delegate = self;
        [stickerKeyboard registerWithView:self];
        return stickerKeyboard;
    } else {
        return _stickerKeyboard;
    }
}

// This getter can be used to access attachmentKeyboard without triggering lazy creation.
- (nullable AttachmentKeyboard *)attachmentKeyboardIfSet
{
    return _attachmentKeyboard;
}

- (AttachmentKeyboard *)attachmentKeyboard
{
    // Lazy-create. This keyboard is expensive to build and can
    // delay CVC presentation.
    if (_attachmentKeyboard == nil) {
        AttachmentKeyboard *attachmentKeyboard = [AttachmentKeyboard new];
        _attachmentKeyboard = attachmentKeyboard;
        attachmentKeyboard.delegate = self;
        [attachmentKeyboard registerWithView:self];
        return attachmentKeyboard;
    } else {
        return _attachmentKeyboard;
    }
}

- (void)updateFontSizes
{
    self.inputTextView.font = [UIFont ows_dynamicTypeBodyFont];
}

- (nullable MessageBody *)messageBody
{
    OWSAssertDebug(self.inputTextView);

    return self.inputTextView.messageBody;
}

- (nullable TSThreadReplyInfo *)draftReply
{
    OWSAssertDebug(self.inputTextView);
    if (_quotedReply == nil) {
        return nil;
    }
    return [[TSThreadReplyInfo alloc] initWithTimestamp:_quotedReply.timestamp
                                          authorAddress:_quotedReply.authorAddress];
}

- (void)setMessageBody:(nullable MessageBody *)value animated:(BOOL)isAnimated
{
    [self setMessageBody:value animated:isAnimated doLayout:YES];
}

- (void)setMessageBody:(nullable MessageBody *)value animated:(BOOL)isAnimated doLayout:(BOOL)doLayout
{
    OWSAssertDebug(self.inputTextView);

    self.inputTextView.messageBody = value;

    // It's important that we set the textViewHeight before
    // doing any animation in `ensureButtonVisibilityWithIsAnimated`
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

    if (value.text.length > 0) {
        [self clearDesiredKeyboard];
    }

    [self ensureButtonVisibilityWithIsAnimated:isAnimated doLayout:doLayout];
}

- (void)ensureTextViewHeight
{
    [self updateHeightWithTextView:self.inputTextView];
}

- (void)acceptAutocorrectSuggestion
{
    [self.inputTextView acceptAutocorrectSuggestion];
}

- (void)clearTextMessageAnimated:(BOOL)isAnimated
{
    [self setMessageBody:nil animated:isAnimated];
    [self.inputTextView.undoManager removeAllActions];
    self.wasLinkPreviewCancelled = NO;
}

+ (NSTimeInterval)quotedReplyAnimationDuration
{
    return 0.2;
}

- (void)setQuotedReply:(nullable OWSQuotedReplyModel *)quotedReply
{
    if (quotedReply == _quotedReply) {
        return;
    }

    void (^cleanupSubviewsBlock)(void) = ^{
        for (UIView *subview in self.quotedReplyWrapper.subviews) {
            [subview removeFromSuperview];
        }
    };
    _quotedReply = quotedReply;

    [self.layer removeAllAnimations];

    if (!quotedReply) {
        self.isAnimatingQuotedReply = YES;
        [UIView animateWithDuration:[[self class] quotedReplyAnimationDuration]
            animations:^{ self.quotedReplyWrapper.hidden = YES; }
            completion:^(BOOL finished) {
                self.isAnimatingQuotedReply = NO;
                cleanupSubviewsBlock();
                [self layoutIfNeeded];
            }];
        [self ensureButtonVisibilityWithIsAnimated:NO doLayout:YES];
        return;
    }

    cleanupSubviewsBlock();

    QuotedReplyPreview *quotedMessagePreview =
        [[QuotedReplyPreview alloc] initWithQuotedReply:quotedReply conversationStyle:self.conversationStyle];
    quotedMessagePreview.delegate = self;
    [quotedMessagePreview setContentHuggingHorizontalLow];
    [quotedMessagePreview setCompressionResistanceHorizontalLow];

    self.quotedReplyWrapper.layoutMargins = UIEdgeInsetsZero;
    [self.quotedReplyWrapper addSubview:quotedMessagePreview];
    [quotedMessagePreview autoPinEdgesToSuperviewMargins];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, quotedMessagePreview);

    // hasAsymmetricalRounding may have changed.
    [self clearLinkPreviewView];
    [self updateInputLinkPreview];
    if (self.quotedReplyWrapper.isHidden) {
        self.isAnimatingQuotedReply = YES;
        [UIView animateWithDuration:[[self class] quotedReplyAnimationDuration]
            animations:^{ self.quotedReplyWrapper.hidden = NO; }
            completion:^(BOOL finished) { self.isAnimatingQuotedReply = NO; }];
    }

    [self clearDesiredKeyboard];
}

- (CGFloat)quotedMessageTopMargin
{
    return 5.f;
}

- (void)beginEditingMessage
{
    if (!self.desiredFirstResponder.isFirstResponder) {
        [self.desiredFirstResponder becomeFirstResponder];
    }
}

- (void)endEditingMessage
{
    [self.inputTextView resignFirstResponder];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-result"
    [self.stickerKeyboardIfSet resignFirstResponder];
    [self.attachmentKeyboardIfSet resignFirstResponder];
#pragma clang diagnostic pop
}

- (BOOL)isInputViewFirstResponder
{
    return (self.inputTextView.isFirstResponder || self.stickerKeyboardIfSet.isFirstResponder
        || self.attachmentKeyboardIfSet.isFirstResponder);
}

- (void)ensureButtonVisibilityWithIsAnimated:(BOOL)isAnimated doLayout:(BOOL)doLayout
{
    __block BOOL didChangeLayout = NO;
    void (^ensureViewHiddenState)(UIView *, BOOL) = ^(UIView *subview, BOOL hidden) {
        if (subview.isHidden != hidden) {
            subview.hidden = hidden;
            didChangeLayout = YES;
        }
    };

    // NOTE: We use untrimmedText, so that the sticker button disappears
    //       even if the user just enters whitespace.
    BOOL hasTextInput = self.inputTextView.untrimmedText.length > 0;
    BOOL isShowingVoiceMemoUI = self.isShowingVoiceMemoUI;

    // We used trimmed text for determining all the other button visibility.
    BOOL hasNonWhitespaceTextInput = self.inputTextView.trimmedText.length > 0;
    ensureViewHiddenState(self.attachmentButton, NO);
    if (isShowingVoiceMemoUI) {
        BOOL hideSendButton = self.voiceMemoRecordingState == VoiceMemoRecordingState_RecordingHeld;
        ensureViewHiddenState(self.linkPreviewWrapper, YES);
        ensureViewHiddenState(self.voiceMemoContentView, NO);
        ensureViewHiddenState(self.voiceMemoContentViewLeftSpacer, NO);
        ensureViewHiddenState(self.voiceMemoContentViewRightSpacer, !hideSendButton);
        ensureViewHiddenState(self.cameraButton, YES);
        ensureViewHiddenState(self.voiceMemoButton, YES);
        ensureViewHiddenState(self.sendButton, hideSendButton);
        ensureViewHiddenState(self.attachmentButton, YES);
    } else if (hasNonWhitespaceTextInput) {
        ensureViewHiddenState(self.linkPreviewWrapper, NO);
        ensureViewHiddenState(self.voiceMemoContentView, YES);
        ensureViewHiddenState(self.voiceMemoContentViewLeftSpacer, YES);
        ensureViewHiddenState(self.voiceMemoContentViewRightSpacer, YES);
        ensureViewHiddenState(self.cameraButton, YES);
        ensureViewHiddenState(self.voiceMemoButton, YES);
        ensureViewHiddenState(self.sendButton, NO);
        ensureViewHiddenState(self.attachmentButton, NO);
    } else {
        ensureViewHiddenState(self.linkPreviewWrapper, NO);
        ensureViewHiddenState(self.voiceMemoContentView, YES);
        ensureViewHiddenState(self.voiceMemoContentViewLeftSpacer, YES);
        ensureViewHiddenState(self.voiceMemoContentViewRightSpacer, YES);
        ensureViewHiddenState(self.cameraButton, NO);
        ensureViewHiddenState(self.voiceMemoButton, NO);
        ensureViewHiddenState(self.sendButton, YES);
        ensureViewHiddenState(self.attachmentButton, NO);
    }

    // If the layout has changed, update the layout
    // of the "media and send" stack immediately,
    // to avoid a janky animation where these buttons
    // move around far from their final positions.
    if (doLayout && didChangeLayout) {
        [self.mediaAndSendStack setNeedsLayout];
        [self.mediaAndSendStack layoutIfNeeded];
    }

    void (^updateBlock)(void) = ^{
        BOOL hideStickerButton = hasTextInput || isShowingVoiceMemoUI || self.quotedReply != nil;
        ensureViewHiddenState(self.stickerButton, hideStickerButton);
        if (!hideStickerButton) {
            self.stickerButton.imageView.tintColor
                = (self.desiredKeyboardType == KeyboardType_Sticker ? UIColor.ows_accentBlueColor
                                                                    : Theme.primaryIconColor);
        }

        [self.attachmentButton setSelected:self.desiredKeyboardType == KeyboardType_Attachment animated:isAnimated];

        [self updateSuggestedStickers];
    };

    // we had some strange effects (invisible text areas) animating the final [self layoutIfNeeded] block
    // this approach seems to be a valid workaround
    if (isAnimated) {
        [UIView animateWithDuration:0.1 animations:updateBlock completion:^(BOOL finished) {
            if (doLayout) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self layoutIfNeeded];
                });
            }
        }];
    } else {
        updateBlock();
        if (doLayout) {
            [self layoutIfNeeded];
        }
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
        [self.outerStack autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:self.receivedSafeAreaInsets.left],
        [self.outerStack autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:self.receivedSafeAreaInsets.right],
    ];
}

- (void)updateLayoutWithSafeAreaInsets:(UIEdgeInsets)safeAreaInsets
{
    BOOL didChange = !UIEdgeInsetsEqualToEdgeInsets(self.receivedSafeAreaInsets, safeAreaInsets);
    BOOL hasLayout = self.layoutContraints != nil;

    if (didChange || !hasLayout) {
        self.receivedSafeAreaInsets = safeAreaInsets;

        [self updateContentLayout];
    }
}

- (void)handleLongPress:(UIGestureRecognizer *)sender
{
    switch (sender.state) {
        case UIGestureRecognizerStatePossible:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            if (self.voiceMemoRecordingState != VoiceMemoRecordingState_Idle) {
                // Record a draft if we were actively recording.
                self.voiceMemoRecordingState = VoiceMemoRecordingState_Idle;
                [self.inputToolbarDelegate voiceMemoGestureWasInterrupted];
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
                case VoiceMemoRecordingState_Draft:
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
            if (self.isShowingVoiceMemoUI) {
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
                            [self setVoiceMemoUICancelAlpha:0];
                            break;
                        case VoiceMemoRecordingState_RecordingLocked:
                        case VoiceMemoRecordingState_Draft:
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
                        [self setVoiceMemoUICancelAlpha:cancelAlpha];
                    }

                    if (xOffset > yOffset) {
                        self.voiceMemoRedRecordingCircle.transform
                            = CGAffineTransformMakeTranslation(MIN(-xOffset, 0), 0);
                    } else if (yOffset > xOffset) {
                        self.voiceMemoRedRecordingCircle.transform
                            = CGAffineTransformMakeTranslation(0, MIN(-yOffset, 0));
                    } else {
                        self.voiceMemoRedRecordingCircle.transform = CGAffineTransformIdentity;
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
                case VoiceMemoRecordingState_Draft:
                    // Continue recording.
                    break;
            }
            break;
    }
}

- (void)setVoiceMemoRecordingState:(VoiceMemoRecordingState)voiceMemoRecordingState
{
    OWSAssertIsOnMainThread();

    if (voiceMemoRecordingState != _voiceMemoRecordingState) {
        _voiceMemoRecordingState = voiceMemoRecordingState;
        [self ensureButtonVisibilityWithIsAnimated:YES doLayout:YES];
    }
}

- (void)setIsShowingVoiceMemoUI:(BOOL)isShowingVoiceMemoUI
{
    OWSAssertIsOnMainThread();

    if (isShowingVoiceMemoUI != _isShowingVoiceMemoUI) {
        _isShowingVoiceMemoUI = isShowingVoiceMemoUI;
        [self ensureButtonVisibilityWithIsAnimated:YES doLayout:YES];
    }
}

#pragma mark - Voice Memo

- (void)showVoiceMemoUI
{
    OWSAssertIsOnMainThread();

    self.isShowingVoiceMemoUI = YES;

    [self removeVoiceMemoTooltip];

    self.voiceMemoStartTime = [NSDate date];

    [self.voiceMemoRedRecordingCircle removeFromSuperview];
    [self.voiceMemoLockView removeFromSuperview];

    [self.voiceMemoContentView removeAllSubviews];

    self.recordingLabel = [UILabel new];
    self.recordingLabel.textAlignment = NSTextAlignmentLeft;
    self.recordingLabel.textColor = Theme.primaryTextColor;
    self.recordingLabel.font = UIFont.ows_dynamicTypeBodyClampedFont.ows_medium.ows_monospaced;
    [self.voiceMemoContentView addSubview:self.recordingLabel];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _recordingLabel);

    [self updateVoiceMemo];

    UIImage *icon = [UIImage imageNamed:@"mic-solid-24"];
    OWSAssertDebug(icon);
    UIImageView *imageView =
        [[UIImageView alloc] initWithImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    imageView.tintColor = UIColor.ows_accentRedColor;
    [imageView setContentHuggingHigh];
    [self.voiceMemoContentView addSubview:imageView];

    NSMutableAttributedString *cancelString = [NSMutableAttributedString new];
    const CGFloat cancelArrowFontSize = ScaleFromIPhone5To7Plus(18.4, 20.f);
    NSString *arrowHead = @"\uf104";
    [cancelString append:arrowHead
              attributes:@{
                  NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                  NSForegroundColorAttributeName : Theme.secondaryTextAndIconColor,
                  NSBaselineOffsetAttributeName : @(-1.f),
              }];
    [cancelString append:@"  "
              attributes:@{
                  NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                  NSForegroundColorAttributeName : Theme.secondaryTextAndIconColor,
                  NSBaselineOffsetAttributeName : @(-1.f),
              }];
    [cancelString
            append:NSLocalizedString(@"VOICE_MESSAGE_CANCEL_INSTRUCTIONS", @"Indicates how to cancel a voice message.")
        attributes:@{
            NSFontAttributeName : [UIFont ows_dynamicTypeSubheadlineClampedFont],
            NSForegroundColorAttributeName : Theme.secondaryTextAndIconColor,
        }];
    UILabel *cancelLabel = [UILabel new];
    cancelLabel.textAlignment = NSTextAlignmentRight;
    self.voiceMemoCancelLabel = cancelLabel;
    cancelLabel.attributedText = cancelString;
    [self.voiceMemoContentView addSubview:cancelLabel];

    const CGFloat kRedCircleSize = 80.f;
    UIView *redCircleView = [[OWSCircleView alloc] initWithDiameter:kRedCircleSize];
    self.voiceMemoRedRecordingCircle = redCircleView;
    redCircleView.backgroundColor = UIColor.ows_accentRedColor;
    [self addSubview:redCircleView];
    [redCircleView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.voiceMemoContentView];
    [redCircleView autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:12];

    UIImage *whiteIcon = [UIImage imageNamed:@"mic-solid-36"];
    OWSAssertDebug(whiteIcon);
    UIImageView *whiteIconView = [[UIImageView alloc] initWithImage:whiteIcon];
    [redCircleView addSubview:whiteIconView];
    [whiteIconView autoCenterInSuperview];

    [imageView autoVCenterInSuperview];
    [imageView autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:12.f];
    [self.recordingLabel autoVCenterInSuperview];
    [self.recordingLabel autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:imageView withOffset:8.f];
    [cancelLabel autoVCenterInSuperview];
    [cancelLabel autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:72.f];
    [cancelLabel autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:self.recordingLabel];

    VoiceMemoLockView *voiceMemoLockView = [VoiceMemoLockView new];
    self.voiceMemoLockView = voiceMemoLockView;
    [self insertSubview:voiceMemoLockView belowSubview:redCircleView];
    [voiceMemoLockView autoAlignAxis:ALAxisVertical toSameAxisOfView:redCircleView];
    [voiceMemoLockView autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:redCircleView];
    [voiceMemoLockView setCompressionResistanceHigh];

    voiceMemoLockView.transform = CGAffineTransformMakeScale(0.0, 0.0);
    [voiceMemoLockView layoutIfNeeded];
    [UIView animateWithDuration:0.2f
                          delay:1.f
                        options:0
                     animations:^{
                         voiceMemoLockView.transform = CGAffineTransformIdentity;
                     }
                     completion:nil];

    redCircleView.transform = CGAffineTransformMakeScale(0.0, 0.0);
    [UIView animateWithDuration:0.2f animations:^{ redCircleView.transform = CGAffineTransformIdentity; }];

    // Pulse the icon.
    imageView.alpha = 1.f;
    [UIView animateWithDuration:0.5f
                          delay:0.2f
                        options:UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse
                        | UIViewAnimationOptionCurveEaseIn
                     animations:^{ imageView.alpha = 0.f; }
                     completion:nil];


    [self.voiceMemoUpdateTimer invalidate];
    self.voiceMemoUpdateTimer = [NSTimer weakScheduledTimerWithTimeInterval:0.1f
                                                                     target:self
                                                                   selector:@selector(updateVoiceMemo)
                                                                   userInfo:nil
                                                                    repeats:YES];
}

- (void)showVoiceMemoDraft:(VoiceMessageModel *)voiceMemoDraft
{
    OWSAssertIsOnMainThread();

    self.isShowingVoiceMemoUI = YES;

    self.voiceMemoDraft = voiceMemoDraft;
    self.voiceMemoRecordingState = VoiceMemoRecordingState_Draft;

    [self removeVoiceMemoTooltip];

    [self.voiceMemoRedRecordingCircle removeFromSuperview];
    [self.voiceMemoLockView removeFromSuperview];

    [self.voiceMemoContentView removeAllSubviews];

    [self.voiceMemoUpdateTimer invalidate];
    self.voiceMemoUpdateTimer = nil;

    __weak __typeof(self) weakSelf = self;
    UIView *draftView = [[VoiceMessageDraftView alloc] initWithVoiceMessageModel:voiceMemoDraft
                                                                      mediaCache:self.mediaCache
                                                               didDeleteCallback:^{ [weakSelf hideVoiceMemoUI:YES]; }];
    [self.voiceMemoContentView addSubview:draftView];
    [draftView autoPinEdgesToSuperviewEdges];
}

- (void)hideVoiceMemoUI:(BOOL)animated
{
    OWSAssertIsOnMainThread();

    self.isShowingVoiceMemoUI = NO;

    [self.voiceMemoContentView removeAllSubviews];

    self.voiceMemoRecordingState = VoiceMemoRecordingState_Idle;
    self.voiceMemoDraft = nil;

    UIView *oldVoiceMemoRedRecordingCircle = self.voiceMemoRedRecordingCircle;
    UIView *oldVoiceMemoLockView = self.voiceMemoLockView;

    self.voiceMemoCancelLabel = nil;
    self.voiceMemoRedRecordingCircle = nil;
    self.voiceMemoLockView = nil;
    self.recordingLabel = nil;

    [self.voiceMemoUpdateTimer invalidate];
    self.voiceMemoUpdateTimer = nil;

    self.voiceMemoDraft = nil;

    if (animated) {
        [UIView animateWithDuration:0.2f
            animations:^{
                oldVoiceMemoRedRecordingCircle.alpha = 0.f;
                oldVoiceMemoLockView.alpha = 0.f;
            }
            completion:^(BOOL finished) {
                [oldVoiceMemoRedRecordingCircle removeFromSuperview];
                [oldVoiceMemoLockView removeFromSuperview];
            }];
    } else {
        [oldVoiceMemoRedRecordingCircle removeFromSuperview];
        [oldVoiceMemoLockView removeFromSuperview];
    }
}

- (void)lockVoiceMemoUI
{
    __weak __typeof(self) weakSelf = self;

    [ImpactHapticFeedback impactOccuredWithStyle:UIImpactFeedbackStyleMedium];

    UIButton *cancelButton = [[OWSButton alloc] initWithBlock:^{
        [weakSelf.inputToolbarDelegate voiceMemoGestureDidCancel];
    }];

    [cancelButton setTitle:CommonStrings.cancelButton forState:UIControlStateNormal];
    [cancelButton setTitleColor:UIColor.ows_accentRedColor forState:UIControlStateNormal];
    [cancelButton setTitleColor:[UIColor.ows_accentRedColor colorWithAlphaComponent:0.4]
                       forState:UIControlStateHighlighted];
    cancelButton.alpha = 0;
    cancelButton.titleLabel.textAlignment = NSTextAlignmentRight;
    cancelButton.titleLabel.font = UIFont.ows_dynamicTypeBodyClampedFont.ows_medium;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, cancelButton);

    [self.voiceMemoContentView addSubview:cancelButton];
    OWSAssert(self.recordingLabel != nil);
    [self.recordingLabel setContentHuggingHigh];

    [NSLayoutConstraint autoSetPriority:UILayoutPriorityDefaultLow
                         forConstraints:^{
                             [cancelButton autoHCenterInSuperview];
                         }];
    [cancelButton autoPinEdgeToSuperviewMargin:ALEdgeRight withInset:40];
    [cancelButton autoPinEdge:ALEdgeLeft
                       toEdge:ALEdgeRight
                       ofView:self.recordingLabel
                   withOffset:4
                     relation:NSLayoutRelationGreaterThanOrEqual];
    [cancelButton autoVCenterInSuperview];

    [self.voiceMemoCancelLabel removeFromSuperview];
    [self.voiceMemoContentView layoutIfNeeded];
    [UIView animateWithDuration:0.2f
        animations:^{
            self.voiceMemoRedRecordingCircle.alpha = 0;
            self.voiceMemoLockView.alpha = 0;
            cancelButton.alpha = 1.0;
        }
        completion:^(BOOL finished) {
            [self.voiceMemoRedRecordingCircle removeFromSuperview];
            [self.voiceMemoLockView removeFromSuperview];
            UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, Nil);
        }];
}

- (void)setVoiceMemoUICancelAlpha:(CGFloat)cancelAlpha
{
    OWSAssertIsOnMainThread();

    // Fade out the voice message views as the cancel gesture
    // proceeds as feedback.
    self.voiceMemoCancelLabel.alpha = MAX(0.f, MIN(1.f, 1.f - (float)cancelAlpha));
}

- (void)updateVoiceMemo
{
    OWSAssertIsOnMainThread();

    NSTimeInterval durationSeconds = fabs([self.voiceMemoStartTime timeIntervalSinceNow]);
    self.recordingLabel.text = [OWSFormat formatDurationSeconds:(long)round(durationSeconds)];
    [self.recordingLabel sizeToFit];
}

- (void)showVoiceMemoTooltip
{
    if (self.voiceMemoTooltip) {
        return;
    }

    __weak ConversationInputToolbar *weakSelf = self;
    UIView *tooltip = [VoiceMessageTooltip presentFromView:self
                                        widthReferenceView:self
                                         tailReferenceView:self.voiceMemoButton
                                            wasTappedBlock:^{ [weakSelf removeVoiceMemoTooltip]; }];
    self.voiceMemoTooltip = tooltip;

    const CGFloat tooltipDurationSeconds = 3.f;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(tooltipDurationSeconds * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{ [weakSelf removeVoiceMemoTooltip]; });
}

- (void)removeVoiceMemoTooltip
{
    UIView *voiceMemoTooltip = self.voiceMemoTooltip;
    self.voiceMemoTooltip = nil;

    [UIView animateWithDuration:0.2
        animations:^{ voiceMemoTooltip.alpha = 0; }
        completion:^(BOOL finished) { [voiceMemoTooltip removeFromSuperview]; }];
}

#pragma mark - Event Handlers

- (void)sendButtonPressed
{
    OWSAssertDebug(self.inputToolbarDelegate);

    if (self.isShowingVoiceMemoUI) {
        self.voiceMemoRecordingState = VoiceMemoRecordingState_Idle;

        if (self.voiceMemoDraft) {
            [self.inputToolbarDelegate sendVoiceMemoDraft:self.voiceMemoDraft];
        } else {
            [self.inputToolbarDelegate voiceMemoGestureDidComplete];
        }
    } else {
        [self.inputToolbarDelegate sendButtonPressed];
    }
}

- (void)cameraButtonPressed
{
    OWSAssertDebug(self.inputToolbarDelegate);

    [ImpactHapticFeedback impactOccuredWithStyle:UIImpactFeedbackStyleLight];

    [self.inputToolbarDelegate cameraButtonPressed];
}

- (void)attachmentButtonPressed
{
    OWSLogVerbose(@"");

    [ImpactHapticFeedback impactOccuredWithStyle:UIImpactFeedbackStyleLight];

    [self toggleKeyboardType:KeyboardType_Attachment animated:YES];
}

- (void)stickerButtonPressed
{
    OWSLogVerbose(@"");

    [ImpactHapticFeedback impactOccuredWithStyle:UIImpactFeedbackStyleLight];

    __block BOOL hasInstalledStickerPacks;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        hasInstalledStickerPacks = [StickerManager installedStickerPacksWithTransaction:transaction].count > 0;
    }];
    if (!hasInstalledStickerPacks) {
        // If the keyboard is presented and no stickers are installed,
        // show the manage stickers view. Do not show the sticker keyboard.
        [self presentManageStickersView];
        return;
    }

    [self toggleKeyboardType:KeyboardType_Sticker animated:YES];
}

#pragma mark - Keyboards

- (void)toggleKeyboardType:(KeyboardType)keyboardType animated:(BOOL)animated
{
    OWSAssertDebug(self.inputToolbarDelegate);

    if (self.desiredKeyboardType == keyboardType) {
        [self setDesiredKeyboardType:KeyboardType_System animated:animated];
    } else {
        // For switching to anything other than the system keyboard,
        // make sure this conversation isn't blocked before presenting it.
        if ([self.inputToolbarDelegate isBlockedConversation]) {
            __weak ConversationInputToolbar *weakSelf = self;
            [self.inputToolbarDelegate showUnblockConversationUI:^(BOOL isBlocked) {
                if (!isBlocked) {
                    [weakSelf toggleKeyboardType:keyboardType animated:animated];
                }
            }];
            return;
        }

        [self setDesiredKeyboardType:keyboardType animated:animated];
    }

    [self beginEditingMessage];
}

- (void)setDesiredKeyboardType:(KeyboardType)desiredKeyboardType
{
    [self setDesiredKeyboardType:desiredKeyboardType animated:NO];
}

- (void)setDesiredKeyboardType:(KeyboardType)desiredKeyboardType animated:(BOOL)animated
{
    if (_desiredKeyboardType == desiredKeyboardType) {
        return;
    }

    _desiredKeyboardType = desiredKeyboardType;

    [self ensureButtonVisibilityWithIsAnimated:animated doLayout:YES];

    if (self.isInputViewFirstResponder) {
        // If any keyboard is presented, make sure the correct
        // keyboard is presented.
        [self beginEditingMessage];
    } else {
        // Make sure neither keyboard is presented.
        [self endEditingMessage];
    }
}

- (void)clearDesiredKeyboard
{
    OWSAssertIsOnMainThread();

    self.desiredKeyboardType = KeyboardType_System;
}

- (UIResponder *)desiredFirstResponder
{
    switch (self.desiredKeyboardType) {
        case KeyboardType_System:
            return self.inputTextView;
        case KeyboardType_Sticker:
            return self.stickerKeyboard;
        case KeyboardType_Attachment:
            return self.attachmentKeyboard;
    }
}

- (void)showStickerKeyboard
{
    OWSAssertIsOnMainThread();

    if (self.desiredKeyboardType != KeyboardType_Sticker) {
        [self toggleKeyboardType:KeyboardType_Sticker animated:NO];
    }
}

- (void)showAttachmentKeyboard
{
    OWSAssertIsOnMainThread();

    if (self.desiredKeyboardType != KeyboardType_Attachment) {
        [self toggleKeyboardType:KeyboardType_Attachment animated:NO];
    }
}

#pragma mark - ConversationTextViewToolbarDelegate

- (void)setFrame:(CGRect)frame
{
    BOOL didChange = frame.size.height != self.frame.size.height;

    [super setFrame:frame];

    if (didChange) {
        [self.inputToolbarDelegate updateToolbarHeight];
    }
}

- (void)setBounds:(CGRect)bounds
{
    BOOL didChange = bounds.size.height != self.bounds.size.height;

    [super setBounds:bounds];

    // Compensate for autolayout frame/bounds changes when animating in/out the quoted reply view.
    // This logic ensures the input toolbar stays pinned to the keyboard visually
    if (didChange && self.isAnimatingQuotedReply && self.inputTextView.isFirstResponder) {
        CGRect frame = self.frame;
        frame.origin.y = 0;
        // In this conditional, bounds change is captured in an animation block, which we don't want here.
        [UIView performWithoutAnimation:^{ [self setFrame:frame]; }];
    }

    if (didChange) {
        [self.inputToolbarDelegate updateToolbarHeight];
    }
}

- (void)textViewDidChange:(UITextView *)textView
{
    OWSAssertDebug(self.inputToolbarDelegate);

    if (!self.isConfigurationComplete) {
        // Ignore change events during configuration.
        return;
    }

    [self updateHeightWithTextView:textView];
    [self updateInputLinkPreview];
    [self ensureButtonVisibilityWithIsAnimated:YES doLayout:YES];
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

    CGFloat newHeight = CGFloatClamp(contentSize.height,
        kMinTextViewHeight,
        UIDevice.currentDevice.isIPad ? kMaxIPadTextViewHeight : kMaxTextViewHeight);

    if (newHeight != self.textViewHeight) {
        self.textViewHeight = newHeight;
        OWSAssertDebug(self.textViewHeightConstraint);
        self.textViewHeightConstraint.constant = newHeight;
        [self invalidateIntrinsicContentSize];
    }
}

- (void)textViewDidBecomeFirstResponder:(UITextView *)textView
{
    self.desiredKeyboardType = KeyboardType_System;
}

#pragma mark QuotedReplyPreviewViewDelegate

- (void)quotedReplyPreviewDidPressCancel:(QuotedReplyPreview *)preview
{
    if (SSKDebugFlags.internalLogging) {
        OWSLogInfo(@"");
    }
    self.quotedReply = nil;
}

#pragma mark - Link Preview

- (void)updateInputLinkPreview
{
    OWSAssertIsOnMainThread();

    NSString *bodyText =
        [[self messageBody].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (bodyText.length < 1) {
        [self clearLinkPreviewStateAndView];
        self.wasLinkPreviewCancelled = NO;
        return;
    }

    if (self.wasLinkPreviewCancelled) {
        [self clearLinkPreviewStateAndView];
        return;
    }

    // Don't include link previews for oversize text messages.
    if ([bodyText lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= kOversizeTextMessageSizeThreshold) {
        [self clearLinkPreviewStateAndView];
        return;
    }

    NSURL *previewUrl = [self.linkPreviewManager findFirstValidUrlInSearchString:self.inputTextView.text
                                                             bypassSettingsCheck:NO];
    if (!previewUrl.absoluteString.length) {
        [self clearLinkPreviewStateAndView];
        return;
    }

    if ([self.inputLinkPreview.previewUrl isEqual:previewUrl]) {
        // No need to update.
        return;
    }

    InputLinkPreview *inputLinkPreview = [InputLinkPreview new];
    self.inputLinkPreview = inputLinkPreview;
    self.inputLinkPreview.previewUrl = previewUrl;

    [self ensureLinkPreviewViewWithState:[[LinkPreviewLoading alloc] initWithLinkType:LinkPreviewLinkTypePreview]];

    __weak ConversationInputToolbar *weakSelf = self;
    [self.linkPreviewManager fetchLinkPreviewForUrl:previewUrl]
        .done(^(OWSLinkPreviewDraft *linkPreviewDraft) {
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
        });
}

- (void)ensureLinkPreviewViewWithState:(id<LinkPreviewState>)state
{
    OWSAssertIsOnMainThread();

    // TODO: We could re-use LinkPreviewView now.
    [self clearLinkPreviewView];

    LinkPreviewView *linkPreviewView = [[LinkPreviewView alloc] initWithDraftDelegate:self];
    [linkPreviewView configureForNonCVCWithState:state isDraft:YES hasAsymmetricalRounding:!self.quotedReply];
    self.linkPreviewView = linkPreviewView;

    self.linkPreviewWrapper.hidden = NO;
    [self.linkPreviewWrapper addSubview:linkPreviewView];
    [linkPreviewView autoPinEdgesToSuperviewMargins];
    [self.linkPreviewWrapper layoutIfNeeded];
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

#pragma mark - StickerKeyboardDelegate

- (void)didSelectStickerWithStickerInfo:(StickerInfo *)stickerInfo
{
    OWSAssertIsOnMainThread();

    OWSLogVerbose(@"");

    [self.inputToolbarDelegate sendSticker:stickerInfo];
}

- (void)presentManageStickersView
{
    OWSAssertIsOnMainThread();

    OWSLogVerbose(@"");

    [self.inputToolbarDelegate presentManageStickersView];
}

#pragma mark - Suggested Stickers

- (void)updateSuggestedStickers
{
    NSString *inputText = self.inputTextView.trimmedText;
    NSArray<InstalledSticker *> *suggestedStickers = [StickerManager.shared suggestedStickersForTextInput:inputText];
    NSMutableArray<StickerInfo *> *infos = [NSMutableArray new];
    for (InstalledSticker *installedSticker in suggestedStickers) {
        [infos addObject:installedSticker.info];
    }
    self.suggestedStickerInfos = [infos copy];
}

- (void)setSuggestedStickerInfos:(NSArray<StickerInfo *> *)suggestedStickerInfos
{
    BOOL didChange = ![NSObject isNullableObject:_suggestedStickerInfos equalTo:suggestedStickerInfos];

    _suggestedStickerInfos = suggestedStickerInfos;

    if (didChange) {
        [self updateSuggestedStickerView];
    }
}

- (void)updateSuggestedStickerView
{
    if (self.suggestedStickerInfos.count < 1) {
        self.suggestedStickerView.isHiddenInStackView = YES;
        [self layoutIfNeeded];
        return;
    }
    __weak __typeof(self) weakSelf = self;
    BOOL shouldReset = self.suggestedStickerView.isHidden;
    NSMutableArray<id<StickerHorizontalListViewItem>> *items = [NSMutableArray new];
    for (StickerInfo *stickerInfo in self.suggestedStickerInfos) {
        [items addObject:[[StickerHorizontalListViewItemSticker alloc]
                             initWithStickerInfo:stickerInfo
                                  didSelectBlock:^{ [weakSelf didSelectSuggestedSticker:stickerInfo]; }
                                           cache:self.suggestedStickerViewCache]];
    }
    self.suggestedStickerView.items = items;
    self.suggestedStickerView.isHiddenInStackView = NO;
    [self layoutIfNeeded];
    if (shouldReset) {
        self.suggestedStickerView.contentOffset
            = CGPointMake(-self.suggestedStickerView.contentInset.left, -self.suggestedStickerView.contentInset.top);
    }
}

- (void)didSelectSuggestedSticker:(StickerInfo *)stickerInfo
{
    OWSAssertIsOnMainThread();

    OWSLogVerbose(@"");

    [self clearTextMessageAnimated:YES];
    [self.inputToolbarDelegate sendSticker:stickerInfo];
}

- (void)viewDidAppear
{
    [self ensureButtonVisibilityWithIsAnimated:NO doLayout:NO];
    [self cacheKeyboardIfNecessary];
}

- (void)cacheKeyboardIfNecessary
{
    // Preload the keyboard if we're not showing it already, this
    // allows us to calculate the appropriate initial height for
    // our custom inputViews and in general to present it faster
    // We disable animations so this preload is invisible to the
    // user.
    //
    // We only measure the keyboard if the toolbar isn't hidden.
    // If it's hidden, we're likely here from a peek interaction
    // and don't want to show the keyboard. We'll measure it later.
    if (!self.hasMeasuredKeyboardHeight && !self.inputTextView.isFirstResponder && !self.isHidden) {

        // Flag that we're measuring the system keyboard's height, so
        // even if though it won't be the first responder by the time
        // the notifications fire, we'll still read its measurement
        self.isMeasuringKeyboardHeight = YES;

        [UIView setAnimationsEnabled:NO];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-result"
        [self.inputTextView becomeFirstResponder];
        [self.inputTextView resignFirstResponder];
#pragma clang diagnostic pop
        [self.inputTextView reloadMentionState];
        [UIView setAnimationsEnabled:YES];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self restoreDesiredKeyboardIfNecessary];
}

- (void)ensureFirstResponderState
{
    [self restoreDesiredKeyboardIfNecessary];
}

- (void)restoreDesiredKeyboardIfNecessary
{
    OWSAssertIsOnMainThread();

    if (self.desiredKeyboardType != KeyboardType_System && !self.desiredFirstResponder.isFirstResponder) {
        [self.desiredFirstResponder becomeFirstResponder];
    }
}

- (void)keyboardFrameDidChange:(NSNotification *)notification
{
    NSValue *_Nullable keyboardEndFrameValue = notification.userInfo[UIKeyboardFrameEndUserInfoKey];
    if (!keyboardEndFrameValue) {
        OWSFailDebug(@"Missing keyboard end frame");
        return;
    }
    CGRect keyboardEndFrame = [keyboardEndFrameValue CGRectValue];

    if (self.inputTextView.isFirstResponder || self.isMeasuringKeyboardHeight) {
        // The returned keyboard height includes the input view, so subtract our height.
        CGFloat newHeight = keyboardEndFrame.size.height - self.frame.size.height;
        if (newHeight > 0) {
            [self.stickerKeyboard updateSystemKeyboardHeight:newHeight];
            [self.attachmentKeyboard updateSystemKeyboardHeight:newHeight];
            if (self.isMeasuringKeyboardHeight) {
                self.isMeasuringKeyboardHeight = NO;
                self.hasMeasuredKeyboardHeight = YES;
            }
        }
    }
}

#pragma mark - Attachment Keyboard Delegate

- (void)didSelectRecentPhotoWithAsset:(PHAsset *)asset attachment:(SignalAttachment *)attachment
{
    [self.inputToolbarDelegate didSelectRecentPhotoWithAsset:asset attachment:attachment];
}

- (void)didTapGalleryButton
{
    [self.inputToolbarDelegate galleryButtonPressed];
}

- (void)didTapCamera
{
    [self.inputToolbarDelegate cameraButtonPressed];
}

- (void)didTapGif
{
    [self.inputToolbarDelegate gifButtonPressed];
}

- (void)didTapFile
{
    [self.inputToolbarDelegate fileButtonPressed];
}

- (void)didTapContact
{
    [self.inputToolbarDelegate contactButtonPressed];
}

- (void)didTapLocation
{
    [self.inputToolbarDelegate locationButtonPressed];
}

- (void)updateConversationStyle:(ConversationStyle *)conversationStyle
{
    OWSAssertIsOnMainThread();

    _conversationStyle = conversationStyle;
}

- (void)didTapPayment
{
    [self.inputToolbarDelegate paymentButtonPressed];
}

- (BOOL)isGroup
{
    return self.inputToolbarDelegate.isGroup;
}

@end

NS_ASSUME_NONNULL_END
