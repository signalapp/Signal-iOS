//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "ConversationInputToolbar.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "OWSMath.h"
#import "Signal-Swift.h"
#import "UIFont+OWS.h"
#import "ViewControllerUtils.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalServiceKit/NSTimer+OWS.h>
#import <SignalServiceKit/OWSFormat.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSQuotedMessage.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, VoiceMemoRecordingState){
    VoiceMemoRecordingState_Idle,
    VoiceMemoRecordingState_RecordingHeld,
    VoiceMemoRecordingState_RecordingLocked
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
@property (nonatomic, readonly) UIStackView *outerStack;
@property (nonatomic, readonly) UIStackView *mediaAndSendStack;

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
@property (nonatomic, nullable, weak) UIView *stickerTooltip;
@property (nonatomic) BOOL isConfigurationComplete;

#pragma mark - Keyboards

@property (nonatomic) KeyboardType desiredKeyboardType;
@property (nonatomic, readonly) StickerKeyboard *stickerKeyboard;
@property (nonatomic, readonly) AttachmentKeyboard *attachmentKeyboard;

@end

#pragma mark -

@implementation ConversationInputToolbar

@synthesize stickerKeyboard = _stickerKeyboard;
@synthesize attachmentKeyboard = _attachmentKeyboard;

- (instancetype)initWithConversationStyle:(ConversationStyle *)conversationStyle
                             messageDraft:(nullable MessageBody *)messageDraft
                     inputToolbarDelegate:(id<ConversationInputToolbarDelegate>)inputToolbarDelegate
                    inputTextViewDelegate:(id<ConversationInputTextViewDelegate>)inputTextViewDelegate
                          mentionDelegate:(id<MentionTextViewDelegate>)mentionDelegate
{
    self = [super initWithFrame:CGRectZero];

    _conversationStyle = conversationStyle;
    _receivedSafeAreaInsets = UIEdgeInsetsZero;

    self.inputToolbarDelegate = inputToolbarDelegate;

    if (self) {
        [self createContentsWithMessageDraft:messageDraft
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
                 inputTextViewDelegate:(id<ConversationInputTextViewDelegate>)inputTextViewDelegate
                       mentionDelegate:(id<MentionTextViewDelegate>)mentionDelegate
{
    // The input toolbar should *always* be layed out left-to-right, even when using
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
    CGFloat backgroundExtension = 100;

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
    self.quotedReplyWrapper.hidden = YES;
    [self.quotedReplyWrapper setContentHuggingHorizontalLow];
    [self.quotedReplyWrapper setCompressionResistanceHorizontalLow];
    self.quotedReplyWrapper.backgroundColor = Theme.conversationInputBackgroundColor;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _quotedReplyWrapper);

    _linkPreviewWrapper = [UIView containerView];
    self.linkPreviewWrapper.hidden = YES;
    [self.linkPreviewWrapper setContentHuggingHorizontalLow];
    [self.linkPreviewWrapper setCompressionResistanceHorizontalLow];
    self.linkPreviewWrapper.backgroundColor = Theme.conversationInputBackgroundColor;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _linkPreviewWrapper);

    // V Stack
    UIStackView *vStack = [[UIStackView alloc]
        initWithArrangedSubviews:@[ self.quotedReplyWrapper, self.linkPreviewWrapper, self.inputTextView ]];
    vStack.axis = UILayoutConstraintAxisVertical;
    vStack.alignment = UIStackViewAlignmentFill;
    [vStack setContentHuggingHorizontalLow];
    [vStack setCompressionResistanceHorizontalLow];

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
    self.suggestedStickerView.hidden = YES;
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
        [self ensureButtonVisibilityWithIsAnimated:NO doLayout:YES];
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
    [quotedMessagePreview autoPinEdgesToSuperviewMargins];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, quotedMessagePreview);

    self.linkPreviewView.hasAsymmetricalRounding = !self.quotedReply;

    [self clearDesiredKeyboard];
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

- (void)beginEditingMessage
{
    if (!self.desiredFirstResponder.isFirstResponder) {
        [self.desiredFirstResponder becomeFirstResponder];
    }
}

- (void)showStickerTooltipIfNecessary
{
    if (!StickerManager.shared.shouldShowStickerTooltip) {
        return;
    }

    dispatch_block_t markTooltipAsShown = ^{
        DatabaseStorageAsyncWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            [StickerManager.shared stickerTooltipWasShownWithTransaction:transaction];
        });
    };

    __block StickerPack *_Nullable stickerPack;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        stickerPack = [StickerManager installedStickerPacksWithTransaction:transaction].firstObject;
    }];
    if (stickerPack == nil) {
        return;
    }
    if (self.stickerTooltip != nil) {
        markTooltipAsShown();
        return;
    }
    if (self.desiredKeyboardType == KeyboardType_Sticker) {
        // The intent of this tooltip is to prod users to activate the
        // sticker keyboard.  If it's already active, we can skip the
        // tooltip.
        markTooltipAsShown();
        return;
    }

    __weak ConversationInputToolbar *weakSelf = self;
    UIView *tooltip = [StickerTooltip presentFromView:self
                                   widthReferenceView:self
                                    tailReferenceView:self.stickerButton
                                          stickerPack:stickerPack
                                       wasTappedBlock:^{
                                           [weakSelf removeStickerTooltip];
                                           [weakSelf toggleKeyboardType:KeyboardType_Sticker animated:YES];
                                       }];
    self.stickerTooltip = tooltip;

    const CGFloat tooltipDurationSeconds = 5.f;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(tooltipDurationSeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       [weakSelf removeStickerTooltip];
                   });

    markTooltipAsShown();
}

- (void)removeStickerTooltip
{
    [self.stickerTooltip removeFromSuperview];
    self.stickerTooltip = nil;
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

    // We used trimmed text for determining all the other button visibility.
    BOOL hasNonWhitespaceTextInput = self.inputTextView.trimmedText.length > 0;
    ensureViewHiddenState(self.attachmentButton, NO);
    if (hasNonWhitespaceTextInput) {
        ensureViewHiddenState(self.cameraButton, YES);
        ensureViewHiddenState(self.voiceMemoButton, YES);
        ensureViewHiddenState(self.sendButton, NO);
    } else {
        ensureViewHiddenState(self.cameraButton, NO);
        ensureViewHiddenState(self.voiceMemoButton, NO);
        ensureViewHiddenState(self.sendButton, YES);
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
        BOOL hideStickerButton = hasTextInput || self.quotedReply != nil;
        ensureViewHiddenState(self.stickerButton, hideStickerButton);
        if (!hideStickerButton) {
            self.stickerButton.imageView.tintColor
                = (self.desiredKeyboardType == KeyboardType_Sticker ? UIColor.ows_accentBlueColor
                                                                    : Theme.primaryIconColor);
        }

        [self.attachmentButton setSelected:self.desiredKeyboardType == KeyboardType_Attachment animated:isAnimated];

        [self updateSuggestedStickers];

        if (self.stickerButton.hidden || self.stickerKeyboardIfSet.isFirstResponder) {
            [self removeStickerTooltip];
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

    [self showStickerTooltipIfNecessary];
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
    [self.voiceMemoContentView autoPinEdgesToSuperviewMargins];

    self.recordingLabel = [UILabel new];
    self.recordingLabel.textColor = UIColor.ows_accentRedColor;
    self.recordingLabel.font = [UIFont ows_semiboldFontWithSize:14.f];
    [self.voiceMemoContentView addSubview:self.recordingLabel];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _recordingLabel);

    VoiceMemoLockView *voiceMemoLockView = [VoiceMemoLockView new];
    self.voiceMemoLockView = voiceMemoLockView;
    [self addSubview:voiceMemoLockView];
    [voiceMemoLockView autoPinEdgeToSuperviewMargin:ALEdgeRight];
    [voiceMemoLockView autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:self.voiceMemoContentView];
    [voiceMemoLockView setCompressionResistanceHigh];

    [self updateVoiceMemo];

    UIImage *icon = [UIImage imageNamed:@"mic-outline-24"];
    OWSAssertDebug(icon);
    UIImageView *imageView =
        [[UIImageView alloc] initWithImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    imageView.tintColor = UIColor.ows_accentRedColor;
    [imageView setContentHuggingHigh];
    [self.voiceMemoContentView addSubview:imageView];

    NSMutableAttributedString *cancelString = [NSMutableAttributedString new];
    const CGFloat cancelArrowFontSize = ScaleFromIPhone5To7Plus(18.4, 20.f);
    const CGFloat cancelFontSize = ScaleFromIPhone5To7Plus(14.f, 16.f);
    NSString *arrowHead = @"\uf104";
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:arrowHead
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                                           NSForegroundColorAttributeName : UIColor.ows_accentRedColor,
                                           NSBaselineOffsetAttributeName : @(-1.f),
                                       }]];
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:@"  "
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                                           NSForegroundColorAttributeName : UIColor.ows_accentRedColor,
                                           NSBaselineOffsetAttributeName : @(-1.f),
                                       }]];
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:NSLocalizedString(@"VOICE_MESSAGE_CANCEL_INSTRUCTIONS",
                                                      @"Indicates how to cancel a voice message.")
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_semiboldFontWithSize:cancelFontSize],
                                           NSForegroundColorAttributeName : UIColor.ows_accentRedColor,
                                       }]];
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:@"  "
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                                           NSForegroundColorAttributeName : UIColor.ows_accentRedColor,
                                           NSBaselineOffsetAttributeName : @(-1.f),
                                       }]];
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:arrowHead
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_fontAwesomeFont:cancelArrowFontSize],
                                           NSForegroundColorAttributeName : UIColor.ows_accentRedColor,
                                           NSBaselineOffsetAttributeName : @(-1.f),
                                       }]];
    UILabel *cancelLabel = [UILabel new];
    self.voiceMemoCancelLabel = cancelLabel;
    cancelLabel.attributedText = cancelString;
    [self.voiceMemoContentView addSubview:cancelLabel];

    const CGFloat kRedCircleSize = 100.f;
    UIView *redCircleView = [[OWSCircleView alloc] initWithDiameter:kRedCircleSize];
    self.voiceMemoRedRecordingCircle = redCircleView;
    redCircleView.backgroundColor = UIColor.ows_accentRedColor;
    [self.voiceMemoContentView addSubview:redCircleView];
    [redCircleView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.voiceMemoButton];
    [redCircleView autoAlignAxis:ALAxisVertical toSameAxisOfView:self.voiceMemoButton];

    UIImage *whiteIcon = [UIImage imageNamed:@"mic-outline-64"];
    OWSAssertDebug(whiteIcon);
    UIImageView *whiteIconView = [[UIImageView alloc] initWithImage:whiteIcon];
    [redCircleView addSubview:whiteIconView];
    [whiteIconView autoCenterInSuperview];

    [imageView autoVCenterInSuperview];
    [imageView autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:10.f];
    [self.recordingLabel autoVCenterInSuperview];
    [self.recordingLabel autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:imageView withOffset:5.f];
    [cancelLabel autoVCenterInSuperview];
    [cancelLabel autoHCenterInSuperview];
    [self.voiceMemoUI layoutIfNeeded];

    // Slide in the "slide to cancel" label.
    CGRect cancelLabelStartFrame = cancelLabel.frame;
    CGRect cancelLabelEndFrame = cancelLabel.frame;
    cancelLabelStartFrame.origin.x = self.voiceMemoUI.bounds.size.width;
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
    [sendVoiceMemoButton setTitleColor:UIColor.ows_accentBlueColor forState:UIControlStateNormal];
    sendVoiceMemoButton.alpha = 0;
    [self.voiceMemoContentView addSubview:sendVoiceMemoButton];
    [sendVoiceMemoButton autoPinEdgeToSuperviewMargin:ALEdgeRight withInset:10.f];
    [sendVoiceMemoButton autoVCenterInSuperview];
    [sendVoiceMemoButton setCompressionResistanceHigh];
    [sendVoiceMemoButton setContentHuggingHigh];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, sendVoiceMemoButton);

    UIButton *cancelButton = [[OWSButton alloc] initWithBlock:^{
        [weakSelf.inputToolbarDelegate voiceMemoGestureDidCancel];
    }];
    [cancelButton setTitle:CommonStrings.cancelButton forState:UIControlStateNormal];
    [cancelButton setTitleColor:UIColor.ows_accentRedColor forState:UIControlStateNormal];
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
    [cancelButton autoPinEdge:ALEdgeLeft
                       toEdge:ALEdgeRight
                       ofView:self.recordingLabel
                   withOffset:4
                     relation:NSLayoutRelationGreaterThanOrEqual];
    [cancelButton autoPinEdge:ALEdgeLeft
                       toEdge:ALEdgeRight
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
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
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

    [self ensureButtonVisibilityWithIsAnimated:YES doLayout:YES];
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

    NSURL *previewUrl = [self.linkPreviewManager findFirstValidUrlInSearchString:self.inputTextView.text];
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
        });
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
        self.suggestedStickerView.hidden = YES;
        [self layoutIfNeeded];
        return;
    }
    __weak __typeof(self) weakSelf = self;
    BOOL shouldReset = self.suggestedStickerView.isHidden;
    NSMutableArray<id<StickerHorizontalListViewItem>> *items = [NSMutableArray new];
    for (StickerInfo *stickerInfo in self.suggestedStickerInfos) {
        [items addObject:[[StickerHorizontalListViewItemSticker alloc]
                             initWithStickerInfo:stickerInfo
                                  didSelectBlock:^{
                                      [weakSelf didSelectSuggestedSticker:stickerInfo];
                                  }]];
    }
    self.suggestedStickerView.items = items;
    self.suggestedStickerView.hidden = NO;
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

// stickerTooltip lies outside this view's bounds, so we
// need to special-case the hit testing so that it can
// intercept touches within its bounds.
- (BOOL)pointInside:(CGPoint)point withEvent:(nullable UIEvent *)event
{
    UIView *_Nullable stickerTooltip = self.stickerTooltip;
    if (stickerTooltip != nil) {
        CGRect stickerTooltipFrame = [self convertRect:stickerTooltip.bounds fromView:stickerTooltip];
        if (CGRectContainsPoint(stickerTooltipFrame, point)) {
            return YES;
        }
    }
    return [super pointInside:point withEvent:event];
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
    if (!self.inputTextView.isFirstResponder && !self.isHidden) {

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
            self.isMeasuringKeyboardHeight = NO;
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

@end

NS_ASSUME_NONNULL_END
