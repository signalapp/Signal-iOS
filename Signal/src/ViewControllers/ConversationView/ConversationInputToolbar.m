//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationInputToolbar.h"
#import "ConversationInputTextView.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <JSQMessagesViewController/JSQMessagesToolbarButtonFactory.h>
#import <SignalServiceKit/NSTimer+OWS.h>

NS_ASSUME_NONNULL_BEGIN

@interface ConversationInputToolbar () <UIGestureRecognizerDelegate, UITextViewDelegate>

@property (nonatomic, readonly) ConversationInputTextView *inputTextView;

@property (nonatomic, readonly) UIButton *attachmentButton;

@property (nonatomic, readonly) UIButton *sendButton;

@property (nonatomic) BOOL shouldShowVoiceMemoButton;

@property (nonatomic, nullable) UIButton *voiceMemoButton;

#pragma mark - Voice Memo Recording UI

@property (nonatomic, nullable) UIView *voiceMemoUI;

@property (nonatomic) UIView *voiceMemoContentView;

@property (nonatomic) NSDate *voiceMemoStartTime;

@property (nonatomic, nullable) NSTimer *voiceMemoUpdateTimer;

@property (nonatomic) UILabel *recordingLabel;

@property (nonatomic) BOOL isRecordingVoiceMemo;

@property (nonatomic) CGPoint voiceMemoGestureStartLocation;

@property (nonatomic) NSArray<NSLayoutConstraint *> *contentContraints;

@end

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

- (void)createContents
{
    _inputTextView = [ConversationInputTextView new];
    self.inputTextView.delegate = self;
    [self addSubview:self.inputTextView];

    _attachmentButton = [[UIButton alloc] init];
    self.attachmentButton.accessibilityLabel
        = NSLocalizedString(@"ATTACHMENT_LABEL", @"Accessibility label for attaching photos");
    self.attachmentButton.accessibilityHint = NSLocalizedString(
        @"ATTACHMENT_HINT", @"Accessibility hint describing what you can do with the attachment button");
    [self.attachmentButton addTarget:self
                              action:@selector(attachmentButtonPressed)
                    forControlEvents:UIControlEventTouchUpInside];

    //    [_attachButton setFrame:CGRectMake(0,
    //                                       0,
    //                                       JSQ_TOOLBAR_ICON_WIDTH + JSQ_IMAGE_INSET * 2,
    //                                       JSQ_TOOLBAR_ICON_HEIGHT + JSQ_IMAGE_INSET * 2)];
    //    _attachButton.imageEdgeInsets
    //    = UIEdgeInsetsMake(JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET);
    [self.attachmentButton setImage:[UIImage imageNamed:@"btnAttachments--blue"] forState:UIControlStateNormal];
    [self addSubview:self.attachmentButton];

    // TODO:
    _sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.sendButton
        setTitle:NSLocalizedString(@"SEND_BUTTON_TITLE", @"Label for the send button in the conversation view.")
        forState:UIControlStateNormal];
    [self.sendButton setTitleColor:[UIColor ows_materialBlueColor] forState:UIControlStateNormal];
    self.sendButton.titleLabel.font = [UIFont ows_regularFontWithSize:17.0f];
    self.sendButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.sendButton.titleLabel.font = [UIFont ows_mediumFontWithSize:16.f];
    [self.sendButton addTarget:self action:@selector(sendButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.sendButton];

    UIImage *voiceMemoIcon = [UIImage imageNamed:@"voice-memo-button"];
    OWSAssert(voiceMemoIcon);
    self.voiceMemoButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.voiceMemoButton setImage:[voiceMemoIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                          forState:UIControlStateNormal];
    self.voiceMemoButton.imageView.tintColor = [UIColor ows_materialBlueColor];
    [self addSubview:self.voiceMemoButton];

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

    //    // We want to be permissive about taps on the send button, so we:
    //    //
    //    // * Add the gesture recognizer to the button's superview instead of the button.
    //    // * Filter the touches that the gesture recognizer receives by serving as its
    //    //   delegate.
    //    UITapGestureRecognizer *tapGestureRecognizer =
    //    [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    //    tapGestureRecognizer.delegate = self;
    //    [self addGestureRecognizer:tapGestureRecognizer];

    self.userInteractionEnabled = YES;

    [self ensureShouldShowVoiceMemoButton];

    //    [self ensureVoiceMemoButton];

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
    // TODO: Remove this when we remove the delegate method.
    [self textViewDidChange:self.inputTextView];
}

- (void)clearTextMessage
{
    [self setMessageText:nil];
    [self.inputTextView.undoManager removeAllActions];
}

- (void)setShouldShowVoiceMemoButton:(BOOL)shouldShowVoiceMemoButton
{
    if (_shouldShowVoiceMemoButton == shouldShowVoiceMemoButton) {
        return;
    }

    _shouldShowVoiceMemoButton = shouldShowVoiceMemoButton;

    [self ensureContentConstraints];
}

- (void)beginEditingTextMessage
{
    [self.inputTextView becomeFirstResponder];
}

- (void)endEditingTextMessage
{
    [self.inputTextView resignFirstResponder];
}

- (void)ensureContentConstraints
{
    [NSLayoutConstraint deactivateConstraints:self.contentContraints];

    //    NSMutableArray<NSLayoutConstraint *> *contentContraints = [NSMutableArray new];

    // TODO: RTL, margin, spacing.
    const int textViewVInset = 5;
    const int contentHInset = 5;
    const int contentHSpacing = 5;

    UIView *primaryButton = (self.shouldShowVoiceMemoButton ? self.voiceMemoButton : self.sendButton);
    UIView *otherButton = (self.shouldShowVoiceMemoButton ? self.sendButton : self.voiceMemoButton);
    primaryButton.hidden = NO;
    otherButton.hidden = YES;

    [self.attachmentButton setContentHuggingHigh];
    [primaryButton setContentHuggingHigh];
    [self.inputTextView setContentHuggingLow];

    self.contentContraints = @[
        [self.attachmentButton autoPinLeadingToSuperview],
        [self.attachmentButton autoPinEdgeToSuperviewEdge:ALEdgeTop],
        [self.inputTextView autoPinLeadingToTrailingOfView:self.attachmentButton],
        [self.inputTextView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:textViewVInset],
        [self.inputTextView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:textViewVInset],
        [primaryButton autoPinLeadingToTrailingOfView:self.inputTextView],
        [primaryButton autoPinTrailingToSuperview],
        [primaryButton autoPinEdgeToSuperviewEdge:ALEdgeTop],
    ];

    //    dispatch_async(dispatch_get_main_queue(), ^{
    //        // Wait up to N seconds for database view registrations to
    //        // complete.
    //        [self showImportUIForAttachment:attachment remainingRetries:5];
    //    });
}

- (void)ensureShouldShowVoiceMemoButton
{
    self.shouldShowVoiceMemoButton = self.inputTextView.trimmedText.length < 1;
}

//@interface OWSMessagesToolbarContentView () <UIGestureRecognizerDelegate>
//
//@property (nonatomic) BOOL shouldShowVoiceMemoButton;
//
//@property (nonatomic, nullable) UIButton *voiceMemoButton;
//
//@property (nonatomic, nullable) UIButton *sendButton;
//
//@property (nonatomic) BOOL isRecordingVoiceMemo;
//
//@property (nonatomic) CGPoint voiceMemoGestureStartLocation;
//
//@end
//
//#pragma mark -
//
//@implementation OWSMessagesToolbarContentView
//- (void)setShouldShowVoiceMemoButton:(BOOL)shouldShowVoiceMemoButton
//{
//    if (_shouldShowVoiceMemoButton == shouldShowVoiceMemoButton) {
//        return;
//    }
//
//    _shouldShowVoiceMemoButton = shouldShowVoiceMemoButton;
//
//    [self ensureVoiceMemoButton];
//}+

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

//- (void)handleTap:(UIGestureRecognizer *)sender
//{
//    switch (sender.state) {
//        case UIGestureRecognizerStateRecognized:
//            [self.sendMessageGestureDelegate sendMessageGestureRecognized];
//            break;
//        default:
//            break;
//    }
//}

//- (void)endEditing:(BOOL)force
//{
//    [self.inputTextView endEditing:force];
//}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if ([gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        if (!self.shouldShowVoiceMemoButton) {
            return NO;
        }

        // We want to be permissive about the voice message gesture, so we accept
        // gesture that begin within N points of its bounds.
        CGFloat kVoiceMemoGestureTolerancePoints = 10;
        CGPoint location = [touch locationInView:self.voiceMemoButton];
        CGRect hitTestRect = CGRectInset(
            self.voiceMemoButton.bounds, -kVoiceMemoGestureTolerancePoints, -kVoiceMemoGestureTolerancePoints);
        return CGRectContainsPoint(hitTestRect, location);
        //    } else if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        //        if (self.shouldShowVoiceMemoButton) {
        //            return NO;
        //        }
        //
        //        UIView *sendButton = self.rightBarButtonItem;
        //        // We want to be permissive about taps on the send button, so we accept
        //        // gesture that begin within N points of its bounds.
        //        CGFloat kSendButtonTolerancePoints = 10;
        //        CGPoint location = [touch locationInView:sendButton];
        //        CGRect hitTestRect = CGRectInset(sendButton.bounds, -kSendButtonTolerancePoints,
        //        -kSendButtonTolerancePoints); return CGRectContainsPoint(hitTestRect, location);
    } else {
        return YES;
    }
}


//- (void)toggleSendButtonEnabled
//{
//    // Do nothing; disables JSQ's control over send button enabling.
//    // Overrides a method in JSQMessagesInputToolbar.
//}
//
////- (JSQMessagesToolbarContentView *)loadToolbarContentView
////{
////    NSArray *views = [[OWSMessagesToolbarContentView nib] instantiateWithOwner:nil options:nil];
////    OWSAssert(views.count == 1);
////    OWSMessagesToolbarContentView *view = views[0];
////    OWSAssert([view isKindOfClass:[OWSMessagesToolbarContentView class]]);
////    view.sendMessageGestureDelegate = self;
////    return view;
////}
//


#pragma mark - Voice Memo

- (void)showVoiceMemoUI
{
    OWSAssert([NSThread isMainThread]);

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
    [imageView autoPinLeadingToSuperviewWithMargin:10.f];
    [self.recordingLabel autoVCenterInSuperview];
    [self.recordingLabel autoPinLeadingToTrailingOfView:imageView margin:5.f];
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
    OWSAssert([NSThread isMainThread]);

    UIView *oldVoiceMemoUI = self.voiceMemoUI;
    self.voiceMemoUI = nil;
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
    OWSAssert([NSThread isMainThread]);

    // Fade out the voice message views as the cancel gesture
    // proceeds as feedback.
    self.voiceMemoContentView.layer.opacity = MAX(0.f, MIN(1.f, 1.f - (float)cancelAlpha));
}

- (void)updateVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

    NSTimeInterval durationSeconds = fabs([self.voiceMemoStartTime timeIntervalSinceNow]);
    self.recordingLabel.text = [ViewControllerUtils formatDurationSeconds:(long)round(durationSeconds)];
    [self.recordingLabel sizeToFit];
}

- (void)cancelVoiceMemoIfNecessary
{
    if (self.isRecordingVoiceMemo) {
        self.isRecordingVoiceMemo = NO;
    }
}

//#pragma mark - OWSSendMessageGestureDelegate
//
//- (void)sendMessageGestureRecognized
//{
//    OWSAssert(self.sendButtonOnRight);
//    [self.inputToolbarDelegate messagesInputToolbar:self didPressRightBarButton:self.contentView.rightBarButtonItem];
//}
//


///**
// *  The object that acts as the delegate of the toolbar.
// */
//@property (weak, nonatomic) id<JSQMessagesInputToolbarDelegate> delegate;
//
///**
// *  Returns the content view of the toolbar. This view contains all subviews of the toolbar.
// */
//@property (weak, nonatomic, readonly) JSQMessagesToolbarContentView *contentView;
//
///**
// *  A boolean value indicating whether the send button is on the right side of the toolbar or not.
// *
// *  @discussion The default value is `YES`, which indicates that the send button is the right-most subview of
// *  the toolbar's `contentView`. Set to `NO` to specify that the send button is on the left. This
// *  property is used to determine which touch events correspond to which actions.
// *
// *  @warning Note, this property *does not* change the positions of buttons in the toolbar's content view.
// *  It only specifies whether the `rightBarButtonItem `or the `leftBarButtonItem` is the send button.
// *  The other button then acts as the accessory button.
// */
//@property (assign, nonatomic) BOOL sendButtonOnRight;
//
///**
// *  Specifies the default (minimum) height for the toolbar. The default value is `44.0f`. This value must be positive.
// */
//@property (assign, nonatomic) CGFloat preferredDefaultHeight;
//
///**
// *  Specifies the maximum height for the toolbar. The default value is `NSNotFound`, which specifies no maximum
// height.
// */
//@property (assign, nonatomic) NSUInteger maximumHeight;
//
///**
// *  Enables or disables the send button based on whether or not its `textView` has text.
// *  That is, the send button will be enabled if there is text in the `textView`, and disabled otherwise.
// */
//- (void)toggleSendButtonEnabled;
//
///**
// *  Loads the content view for the toolbar.
// *
// *  @discussion Override this method to provide a custom content view for the toolbar.
// *
// *  @return An initialized `JSQMessagesToolbarContentView` if successful, otherwise `nil`.
// */
//- (JSQMessagesToolbarContentView *)loadToolbarContentView;


//@interface JSQMessagesInputToolbar ()
//
//@property (assign, nonatomic) BOOL jsq_isObserving;
//
//@end
//
//
//
//@implementation JSQMessagesInputToolbar
//
//@dynamic delegate;
//
//#pragma mark - Initialization
//
//- (void)awakeFromNib
//{
//    [super awakeFromNib];
//    [self setTranslatesAutoresizingMaskIntoConstraints:NO];
//
//    self.jsq_isObserving = NO;
//    self.sendButtonOnRight = YES;
//
//    self.preferredDefaultHeight = 44.0f;
//    self.maximumHeight = NSNotFound;
//
//    JSQMessagesToolbarContentView *toolbarContentView = [self loadToolbarContentView];
//    toolbarContentView.frame = self.frame;
//    [self addSubview:toolbarContentView];
//    [self jsq_pinAllEdgesOfSubview:toolbarContentView];
//    [self setNeedsUpdateConstraints];
//    _contentView = toolbarContentView;
//
//    [self jsq_addObservers];
//
//    self.contentView.leftBarButtonItem = [JSQMessagesToolbarButtonFactory defaultAccessoryButtonItem];
//    self.contentView.rightBarButtonItem = [JSQMessagesToolbarButtonFactory defaultSendButtonItem];
//
//    [self toggleSendButtonEnabled];
//}
//
//- (JSQMessagesToolbarContentView *)loadToolbarContentView
//{
//    NSArray *nibViews = [[NSBundle bundleForClass:[JSQMessagesInputToolbar class]]
//    loadNibNamed:NSStringFromClass([JSQMessagesToolbarContentView class])
//                                                                                          owner:nil
//                                                                                        options:nil];
//    return nibViews.firstObject;
//}
//
//- (void)dealloc
//{
//    [self jsq_removeObservers];
//}
//
//#pragma mark - Setters
//
//- (void)setPreferredDefaultHeight:(CGFloat)preferredDefaultHeight
//{
//    NSParameterAssert(preferredDefaultHeight > 0.0f);
//    _preferredDefaultHeight = preferredDefaultHeight;
//}
//
//#pragma mark - Actions
//
//- (void)jsq_leftBarButtonPressed:(UIButton *)sender
//{
//    [self.delegate messagesInputToolbar:self didPressLeftBarButton:sender];
//}
//
//- (void)jsq_rightBarButtonPressed:(UIButton *)sender
//{
//    [self.delegate messagesInputToolbar:self didPressRightBarButton:sender];
//}
//
//#pragma mark - Input toolbar
//
//- (void)toggleSendButtonEnabled
//{
//    BOOL hasText = [self.contentView.textView hasText];
//
//    if (self.sendButtonOnRight) {
//        self.contentView.rightBarButtonItem.enabled = hasText;
//    }
//    else {
//        self.contentView.leftBarButtonItem.enabled = hasText;
//    }
//}
//
//#pragma mark - Key-value observing
//
//- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void
//*)context
//{
//    if (context == kJSQMessagesInputToolbarKeyValueObservingContext) {
//        if (object == self.contentView) {
//
//            if ([keyPath isEqualToString:NSStringFromSelector(@selector(leftBarButtonItem))]) {
//
//                [self.contentView.leftBarButtonItem removeTarget:self
//                                                          action:NULL
//                                                forControlEvents:UIControlEventTouchUpInside];
//
//                [self.contentView.leftBarButtonItem addTarget:self
//                                                       action:@selector(jsq_leftBarButtonPressed:)
//                                             forControlEvents:UIControlEventTouchUpInside];
//            }
//            else if ([keyPath isEqualToString:NSStringFromSelector(@selector(rightBarButtonItem))]) {
//
//                [self.contentView.rightBarButtonItem removeTarget:self
//                                                           action:NULL
//                                                 forControlEvents:UIControlEventTouchUpInside];
//
//                [self.contentView.rightBarButtonItem addTarget:self
//                                                        action:@selector(jsq_rightBarButtonPressed:)
//                                              forControlEvents:UIControlEventTouchUpInside];
//            }
//
//            [self toggleSendButtonEnabled];
//        }
//    }
//}
//
//- (void)jsq_addObservers
//{
//    if (self.jsq_isObserving) {
//        return;
//    }
//
//    [self.contentView addObserver:self
//                       forKeyPath:NSStringFromSelector(@selector(leftBarButtonItem))
//                          options:0
//                          context:kJSQMessagesInputToolbarKeyValueObservingContext];
//
//    [self.contentView addObserver:self
//                       forKeyPath:NSStringFromSelector(@selector(rightBarButtonItem))
//                          options:0
//                          context:kJSQMessagesInputToolbarKeyValueObservingContext];
//
//    self.jsq_isObserving = YES;
//}
//
//- (void)jsq_removeObservers
//{
//    if (!_jsq_isObserving) {
//        return;
//    }
//
//    @try {
//        [_contentView removeObserver:self
//                          forKeyPath:NSStringFromSelector(@selector(leftBarButtonItem))
//                             context:kJSQMessagesInputToolbarKeyValueObservingContext];
//
//        [_contentView removeObserver:self
//                          forKeyPath:NSStringFromSelector(@selector(rightBarButtonItem))
//                             context:kJSQMessagesInputToolbarKeyValueObservingContext];
//    }
//    @catch (NSException *__unused exception) { }
//
//    _jsq_isObserving = NO;
//}


///**
// *  A `JSQMessagesToolbarContentView` represents the content displayed in a `JSQMessagesInputToolbar`.
// *  These subviews consist of a left button, a text view, and a right button. One button is used as
// *  the send button, and the other as the accessory button. The text view is used for composing messages.
// */
//@interface JSQMessagesToolbarContentView : UIView
//
///**
// *  Returns the text view in which the user composes a message.
// */
//@property (weak, nonatomic, readonly) JSQMessagesComposerTextView *textView;
//
///**
// *  A custom button item displayed on the left of the toolbar content view.
// *
// *  @discussion The frame height of this button is ignored. When you set this property, the button
// *  is fitted within a pre-defined default content view, the leftBarButtonContainerView,
// *  whose height is determined by the height of the toolbar. However, the width of this button
// *  will be preserved. You may specify a new width using `leftBarButtonItemWidth`.
// *  If the frame of this button is equal to `CGRectZero` when set, then a default frame size will be used.
// *  Set this value to `nil` to remove the button.
// */
//@property (weak, nonatomic) UIButton *leftBarButtonItem;
//
///**
// *  Specifies the width of the leftBarButtonItem.
// *
// *  @discussion This property modifies the width of the leftBarButtonContainerView.
// */
//@property (assign, nonatomic) CGFloat leftBarButtonItemWidth;
//
///**
// *  Specifies the amount of spacing between the content view and the leading edge of leftBarButtonItem.
// *
// *  @discussion The default value is `8.0f`.
// */
//@property (assign, nonatomic) CGFloat leftContentPadding;
//
///**
// *  The container view for the leftBarButtonItem.
// *
// *  @discussion
// *  You may use this property to add additional button items to the left side of the toolbar content view.
// *  However, you will be completely responsible for responding to all touch events for these buttons
// *  in your `JSQMessagesViewController` subclass.
// */
//@property (weak, nonatomic, readonly) UIView *leftBarButtonContainerView;
//
///**
// *  A custom button item displayed on the right of the toolbar content view.
// *
// *  @discussion The frame height of this button is ignored. When you set this property, the button
// *  is fitted within a pre-defined default content view, the rightBarButtonContainerView,
// *  whose height is determined by the height of the toolbar. However, the width of this button
// *  will be preserved. You may specify a new width using `rightBarButtonItemWidth`.
// *  If the frame of this button is equal to `CGRectZero` when set, then a default frame size will be used.
// *  Set this value to `nil` to remove the button.
// */
//@property (weak, nonatomic) UIButton *rightBarButtonItem;
//
///**
// *  Specifies the width of the rightBarButtonItem.
// *
// *  @discussion This property modifies the width of the rightBarButtonContainerView.
// */
//@property (assign, nonatomic) CGFloat rightBarButtonItemWidth;
//
///**
// *  Specifies the amount of spacing between the content view and the trailing edge of rightBarButtonItem.
// *
// *  @discussion The default value is `8.0f`.
// */
//@property (assign, nonatomic) CGFloat rightContentPadding;
//
///**
// *  The container view for the rightBarButtonItem.
// *
// *  @discussion
// *  You may use this property to add additional button items to the right side of the toolbar content view.
// *  However, you will be completely responsible for responding to all touch events for these buttons
// *  in your `JSQMessagesViewController` subclass.
// */
//@property (weak, nonatomic, readonly) UIView *rightBarButtonContainerView;
//
//#pragma mark - Class methods
//
///**
// *  Returns the `UINib` object initialized for a `JSQMessagesToolbarContentView`.
// *
// *  @return The initialized `UINib` object or `nil` if there were errors during
// *  initialization or the nib file could not be located.
// */
//+ (UINib *)nib;


////
////  Created by Jesse Squires
////  http://www.jessesquires.com
////
////
////  Documentation
////  http://cocoadocs.org/docsets/JSQMessagesViewController
////
////
////  GitHub
////  https://github.com/jessesquires/JSQMessagesViewController
////
////
////  License
////  Copyright (c) 2014 Jesse Squires
////  Released under an MIT license: http://opensource.org/licenses/MIT
////
//
//#import "JSQMessagesToolbarContentView.h"
//
//#import "UIView+JSQMessages.h"
//
// const CGFloat kJSQMessagesToolbarContentViewHorizontalSpacingDefault = 8.0f;
//
//
//@interface JSQMessagesToolbarContentView ()
//
//@property (weak, nonatomic) IBOutlet JSQMessagesComposerTextView *textView;
//
//@property (weak, nonatomic) IBOutlet UIView *leftBarButtonContainerView;
//@property (weak, nonatomic) IBOutlet NSLayoutConstraint *leftBarButtonContainerViewWidthConstraint;
//
//@property (weak, nonatomic) IBOutlet UIView *rightBarButtonContainerView;
//@property (weak, nonatomic) IBOutlet NSLayoutConstraint *rightBarButtonContainerViewWidthConstraint;
//
//@property (weak, nonatomic) IBOutlet NSLayoutConstraint *leftHorizontalSpacingConstraint;
//@property (weak, nonatomic) IBOutlet NSLayoutConstraint *rightHorizontalSpacingConstraint;
//
//@end
//
//
//
//@implementation JSQMessagesToolbarContentView
//
//#pragma mark - Class methods
//
//+ (UINib *)nib
//{
//    return [UINib nibWithNibName:NSStringFromClass([JSQMessagesToolbarContentView class])
//                          bundle:[NSBundle bundleForClass:[JSQMessagesToolbarContentView class]]];
//}
//
//#pragma mark - Initialization
//
//- (void)awakeFromNib
//{
//    [super awakeFromNib];
//
//    [self setTranslatesAutoresizingMaskIntoConstraints:NO];
//
//    self.leftHorizontalSpacingConstraint.constant = kJSQMessagesToolbarContentViewHorizontalSpacingDefault;
//    self.rightHorizontalSpacingConstraint.constant = kJSQMessagesToolbarContentViewHorizontalSpacingDefault;
//
//    self.backgroundColor = [UIColor clearColor];
//}
//
//#pragma mark - Setters
//
//- (void)setBackgroundColor:(UIColor *)backgroundColor
//{
//    [super setBackgroundColor:backgroundColor];
//    self.leftBarButtonContainerView.backgroundColor = backgroundColor;
//    self.rightBarButtonContainerView.backgroundColor = backgroundColor;
//}
//
//- (void)setLeftBarButtonItem:(UIButton *)leftBarButtonItem
//{
//    if (_leftBarButtonItem) {
//        [_leftBarButtonItem removeFromSuperview];
//    }
//
//    if (!leftBarButtonItem) {
//        _leftBarButtonItem = nil;
//        self.leftHorizontalSpacingConstraint.constant = 0.0f;
//        self.leftBarButtonItemWidth = 0.0f;
//        self.leftBarButtonContainerView.hidden = YES;
//        return;
//    }
//
//    if (CGRectEqualToRect(leftBarButtonItem.frame, CGRectZero)) {
//        leftBarButtonItem.frame = self.leftBarButtonContainerView.bounds;
//    }
//
//    self.leftBarButtonContainerView.hidden = NO;
//    self.leftHorizontalSpacingConstraint.constant = kJSQMessagesToolbarContentViewHorizontalSpacingDefault;
//    self.leftBarButtonItemWidth = CGRectGetWidth(leftBarButtonItem.frame);
//
//    [leftBarButtonItem setTranslatesAutoresizingMaskIntoConstraints:NO];
//
//    [self.leftBarButtonContainerView addSubview:leftBarButtonItem];
//    [self.leftBarButtonContainerView jsq_pinAllEdgesOfSubview:leftBarButtonItem];
//    [self setNeedsUpdateConstraints];
//
//    _leftBarButtonItem = leftBarButtonItem;
//}
//
//- (void)setLeftBarButtonItemWidth:(CGFloat)leftBarButtonItemWidth
//{
//    self.leftBarButtonContainerViewWidthConstraint.constant = leftBarButtonItemWidth;
//    [self setNeedsUpdateConstraints];
//}
//
//- (void)setRightBarButtonItem:(UIButton *)rightBarButtonItem
//{
//    if (_rightBarButtonItem) {
//        [_rightBarButtonItem removeFromSuperview];
//    }
//
//    if (!rightBarButtonItem) {
//        _rightBarButtonItem = nil;
//        self.rightHorizontalSpacingConstraint.constant = 0.0f;
//        self.rightBarButtonItemWidth = 0.0f;
//        self.rightBarButtonContainerView.hidden = YES;
//        return;
//    }
//
//    if (CGRectEqualToRect(rightBarButtonItem.frame, CGRectZero)) {
//        rightBarButtonItem.frame = self.rightBarButtonContainerView.bounds;
//    }
//
//    self.rightBarButtonContainerView.hidden = NO;
//    self.rightHorizontalSpacingConstraint.constant = kJSQMessagesToolbarContentViewHorizontalSpacingDefault;
//    self.rightBarButtonItemWidth = CGRectGetWidth(rightBarButtonItem.frame);
//
//    [rightBarButtonItem setTranslatesAutoresizingMaskIntoConstraints:NO];
//
//    [self.rightBarButtonContainerView addSubview:rightBarButtonItem];
//    [self.rightBarButtonContainerView jsq_pinAllEdgesOfSubview:rightBarButtonItem];
//    [self setNeedsUpdateConstraints];
//
//    _rightBarButtonItem = rightBarButtonItem;
//}
//
//- (void)setRightBarButtonItemWidth:(CGFloat)rightBarButtonItemWidth
//{
//    self.rightBarButtonContainerViewWidthConstraint.constant = rightBarButtonItemWidth;
//    [self setNeedsUpdateConstraints];
//}
//
//- (void)setRightContentPadding:(CGFloat)rightContentPadding
//{
//    self.rightHorizontalSpacingConstraint.constant = rightContentPadding;
//    [self setNeedsUpdateConstraints];
//}
//
//- (void)setLeftContentPadding:(CGFloat)leftContentPadding
//{
//    self.leftHorizontalSpacingConstraint.constant = leftContentPadding;
//    [self setNeedsUpdateConstraints];
//}
//
//#pragma mark - Getters
//
//- (CGFloat)leftBarButtonItemWidth
//{
//    return self.leftBarButtonContainerViewWidthConstraint.constant;
//}
//
//- (CGFloat)rightBarButtonItemWidth
//{
//    return self.rightBarButtonContainerViewWidthConstraint.constant;
//}
//
//- (CGFloat)rightContentPadding
//{
//    return self.rightHorizontalSpacingConstraint.constant;
//}
//
//- (CGFloat)leftContentPadding
//{
//    return self.leftHorizontalSpacingConstraint.constant;
//}
//
//#pragma mark - UIView overrides
//
//- (void)setNeedsDisplay
//{
//    [super setNeedsDisplay];
//    [self.textView setNeedsDisplay];
//}
//
//@end

#pragma mark - Event Handlers

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

#pragma mark - UITextViewDelegate

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    //    OWSAssert(self.inputToolbarDelegate);
    OWSAssert(textView == self.inputTextView);

    [textView becomeFirstResponder];

    //    if (self.automaticallyScrollsToMostRecentMessage) {
    //        [self scrollToBottomAnimated:YES];
    //    }
    //    [self.inputToolbarDelegate textViewDidBeginEditing];
}

- (void)textViewDidChange:(UITextView *)textView
{
    OWSAssert(self.inputToolbarDelegate);
    OWSAssert(textView == self.inputTextView);

    [self ensureShouldShowVoiceMemoButton];
    [self.inputToolbarDelegate textViewDidChange];
}

- (void)textViewDidEndEditing:(UITextView *)textView
{
    OWSAssert(textView == self.inputTextView);

    [textView resignFirstResponder];
}

@end

NS_ASSUME_NONNULL_END
