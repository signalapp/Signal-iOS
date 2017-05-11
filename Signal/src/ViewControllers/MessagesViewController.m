//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "MessagesViewController.h"
#import "AppDelegate.h"
#import "AttachmentSharing.h"
#import "BlockListUIUtils.h"
#import "BlockListViewController.h"
#import "DebugUITableViewController.h"
#import "Environment.h"
#import "FingerprintViewController.h"
#import "FullImageViewController.h"
#import "NSDate+millisecondTimeStamp.h"
#import "NewGroupViewController.h"
#import "OWSAudioAttachmentPlayer.h"
#import "OWSCall.h"
#import "OWSCallCollectionViewCell.h"
#import "OWSContactsManager.h"
#import "OWSConversationSettingsTableViewController.h"
#import "OWSConversationSettingsViewDelegate.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSDisplayedMessageCollectionViewCell.h"
#import "OWSExpirableMessageView.h"
#import "OWSIncomingMessageCollectionViewCell.h"
#import "OWSMessageCollectionViewCell.h"
#import "OWSMessagesBubblesSizeCalculator.h"
#import "OWSOutgoingMessageCollectionViewCell.h"
#import "OWSUnknownContactBlockOfferMessage.h"
#import "PropertyListPreferences.h"
#import "Signal-Swift.h"
#import "SignalKeyingStorage.h"
#import "TSAttachmentPointer.h"
#import "TSCall.h"
#import "TSContactThread.h"
#import "TSContentAdapters.h"
#import "TSDatabaseView.h"
#import "TSErrorMessage.h"
#import "TSGenericAttachmentAdapter.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSInvalidIdentityKeyErrorMessage.h"
#import "ThreadUtil.h"
#import "UIFont+OWS.h"
#import "UIUtil.h"
#import "UIViewController+CameraPermissions.h"
#import "UIViewController+OWS.h"
#import "ViewControllerUtils.h"
#import <AddressBookUI/AddressBookUI.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <ContactsUI/CNContactViewController.h>
#import <JSQMessagesViewController/JSQMessagesBubbleImage.h>
#import <JSQMessagesViewController/JSQMessagesBubbleImageFactory.h>
#import <JSQMessagesViewController/JSQMessagesCollectionViewFlowLayoutInvalidationContext.h>
#import <JSQMessagesViewController/JSQMessagesTimestampFormatter.h>
#import <JSQMessagesViewController/JSQSystemSoundPlayer+JSQMessages.h>
#import <JSQMessagesViewController/UIColor+JSQMessages.h>
#import <JSQSystemSoundPlayer.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/NSTimer+OWS.h>
#import <SignalServiceKit/OWSAttachmentsProcessor.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSFingerprint.h>
#import <SignalServiceKit/OWSFingerprintBuilder.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/SignalRecipient.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSInvalidIdentityKeySendingErrorMessage.h>
#import <SignalServiceKit/TSMessagesManager.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/Threading.h>
#import <YapDatabase/YapDatabaseView.h>

@import Photos;

#define kYapDatabaseRangeLength 50
#define kYapDatabaseRangeMaxLength 300
#define kYapDatabaseRangeMinLength 20
#define JSQ_TOOLBAR_ICON_HEIGHT 22
#define JSQ_TOOLBAR_ICON_WIDTH 22
#define JSQ_IMAGE_INSET 5

static NSTimeInterval const kTSMessageSentDateShowTimeInterval = 5 * 60;

NSString *const OWSMessagesViewControllerDidAppearNotification = @"OWSMessagesViewControllerDidAppear";

typedef enum : NSUInteger {
    kMediaTypePicture,
    kMediaTypeVideo,
} kMediaTypes;

@protocol OWSTextViewPasteDelegate <NSObject>

- (void)didPasteAttachment:(SignalAttachment * _Nullable)attachment;

@end

#pragma mark -

@interface OWSMessagesComposerTextView ()

@property (weak, nonatomic) id<OWSTextViewPasteDelegate> textViewPasteDelegate;

@end

#pragma mark -

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

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    if (action == @selector(paste:)) {
        if ([self pasteboardHasPossibleAttachment]) {
            return YES;
        }
    }
    return [super canPerformAction:action withSender:sender];
}

- (void)paste:(id)sender
{
    if ([self pasteboardHasPossibleAttachment]) {
        SignalAttachment *attachment = [SignalAttachment attachmentFromPasteboard];
        // Note: attachment might be nil or have an error at this point; that's fine.
        [self.textViewPasteDelegate didPasteAttachment:attachment];
        return;
    }

    [super paste:sender];
}

@end

#pragma mark -

@protocol OWSMessagesToolbarContentDelegate <NSObject>

- (void)voiceMemoGestureDidStart;

- (void)voiceMemoGestureDidEnd;

- (void)voiceMemoGestureDidCancel;

- (void)voiceMemoGestureDidChange:(CGFloat)cancelAlpha;

@end

#pragma mark -

@interface OWSMessagesToolbarContentView () <UIGestureRecognizerDelegate>

@property (nonatomic, nullable, weak) id<OWSMessagesToolbarContentDelegate> delegate;

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
                [self.delegate voiceMemoGestureDidCancel];
            }
            break;
        case UIGestureRecognizerStateBegan:
            if (self.isRecordingVoiceMemo) {
                // Cancel voice message if necessary.
                self.isRecordingVoiceMemo = NO;
                [self.delegate voiceMemoGestureDidCancel];
            }
            // Start voice message.
            [self.textView resignFirstResponder];
            self.isRecordingVoiceMemo = YES;
            self.voiceMemoGestureStartLocation = [sender locationInView:self];
            [self.delegate voiceMemoGestureDidStart];
            break;
        case UIGestureRecognizerStateChanged:
            if (self.isRecordingVoiceMemo) {
                // Check for "slide to cancel" gesture.
                CGPoint location = [sender locationInView:self];
                CGFloat offset = MAX(0, self.voiceMemoGestureStartLocation.x - location.x);
                // The lower this value, the easier it is to cancel by accident.
                // The higher this value, the harder it is to cancel.
                const CGFloat kCancelOffsetPoints = 100.f;
                CGFloat cancelAlpha = offset / kCancelOffsetPoints;
                BOOL isCancelled = cancelAlpha >= 1.f;
                if (isCancelled) {
                    self.isRecordingVoiceMemo = NO;
                    [self.delegate voiceMemoGestureDidCancel];
                } else {
                    [self.delegate voiceMemoGestureDidChange:cancelAlpha];
                }
            }
            break;
        case UIGestureRecognizerStateEnded:
            if (self.isRecordingVoiceMemo) {
                // End voice message.
                self.isRecordingVoiceMemo = NO;
                [self.delegate voiceMemoGestureDidEnd];
            }
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
    if (self.rightBarButtonItem != self.voiceMemoButton) {
        return NO;
    }

    // We want to be permissive about the voice message gesture, so we accept
    // gesture that begin within N points of the
    CGFloat kVoiceMemoGestureTolerancePoints = 10;
    CGPoint location = [touch locationInView:self.voiceMemoButton];
    CGRect hitTestRect = CGRectInset(
        self.voiceMemoButton.bounds, -kVoiceMemoGestureTolerancePoints, -kVoiceMemoGestureTolerancePoints);
    return CGRectContainsPoint(hitTestRect, location);
}

@end

#pragma mark -

@interface OWSMessagesInputToolbar ()

@property (nonatomic) UIView *voiceMemoUI;

@property (nonatomic) UIView *voiceMemoContentView;

@property (nonatomic) NSDate *voiceMemoStartTime;

@property (nonatomic) NSTimer *voiceMemoUpdateTimer;

@property (nonatomic) UILabel *recordingLabel;

@end

#pragma mark -

@implementation OWSMessagesInputToolbar

- (void)toggleSendButtonEnabled
{
    // Do nothing; disables JSQ's control over send button enabling.
    // Overrides a method in JSQMessagesInputToolbar.
}

- (JSQMessagesToolbarContentView *)loadToolbarContentView {
    NSArray *views = [[OWSMessagesToolbarContentView nib] instantiateWithOwner:nil
                                                                       options:nil];
    OWSAssert(views.count == 1);
    OWSMessagesToolbarContentView *view = views[0];
    OWSAssert([view isKindOfClass:[OWSMessagesToolbarContentView class]]);
    return view;
}

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
    [self.voiceMemoContentView autoPinWidthToSuperview];
    [self.voiceMemoContentView autoPinHeightToSuperview];

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
    [cancelString
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:@"\uf104  "
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
                                   initWithString:@"  \uf104"
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
    [redCircleView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.contentView.rightBarButtonItem];
    [redCircleView autoAlignAxis:ALAxisVertical toSameAxisOfView:self.contentView.rightBarButtonItem];

    UIImage *whiteIcon = [UIImage imageNamed:@"voice-message-large-white"];
    OWSAssert(whiteIcon);
    UIImageView *whiteIconView = [[UIImageView alloc] initWithImage:whiteIcon];
    [redCircleView addSubview:whiteIconView];
    [whiteIconView autoCenterInSuperview];

    [imageView autoVCenterInSuperview];
    [imageView autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:10];
    [self.recordingLabel autoVCenterInSuperview];
    [self.recordingLabel autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:imageView withOffset:5.f];
    [cancelLabel autoVCenterInSuperview];
    [cancelLabel autoHCenterInSuperview];
    [self.voiceMemoUI setNeedsLayout];
    [self.voiceMemoUI layoutSubviews];

    // Slide in the "slide to cancel" label.
    CGRect cancelLabelStartFrame = cancelLabel.frame;
    CGRect cancelLabelEndFrame = cancelLabel.frame;
    cancelLabelStartFrame.origin.x = self.voiceMemoUI.bounds.size.width;
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

@end

#pragma mark -

@interface MessagesViewController () <JSQMessagesComposerTextViewPasteDelegate,
    OWSTextViewPasteDelegate,
    OWSMessagesToolbarContentDelegate,
    OWSConversationSettingsViewDelegate,
    UIDocumentMenuDelegate,
    UIDocumentPickerDelegate> {
    UIImage *tappedImage;
    BOOL isGroupConversation;
}

@property (nonatomic) TSThread *thread;
@property (nonatomic) TSMessageAdapter *lastDeliveredMessage;
@property (nonatomic) YapDatabaseConnection *editingDatabaseConnection;
@property (nonatomic) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic) YapDatabaseViewMappings *messageMappings;

@property (nonatomic) JSQMessagesBubbleImage *outgoingBubbleImageData;
@property (nonatomic) JSQMessagesBubbleImage *incomingBubbleImageData;
@property (nonatomic) JSQMessagesBubbleImage *currentlyOutgoingBubbleImageData;
@property (nonatomic) JSQMessagesBubbleImage *outgoingMessageFailedImageData;

@property (nonatomic) MPMoviePlayerController *videoPlayer;
@property (nonatomic) AVAudioRecorder *audioRecorder;
@property (nonatomic) OWSAudioAttachmentPlayer *audioAttachmentPlayer;

@property (nonatomic) NSTimer *readTimer;
@property (nonatomic) UIView *navigationBarTitleView;
@property (nonatomic) UILabel *navigationBarTitleLabel;
@property (nonatomic) UILabel *navigationBarSubtitleLabel;
@property (nonatomic) UIButton *attachButton;
@property (nonatomic) UIView *blockStateIndicator;

// Back Button Unread Count
@property (nonatomic, readonly) UIView *backButtonUnreadCountView;
@property (nonatomic, readonly) UILabel *backButtonUnreadCountLabel;
@property (nonatomic, readonly) NSUInteger backButtonUnreadCount;

@property (nonatomic) CGFloat previousCollectionViewFrameWidth;

@property (nonatomic) NSUInteger page;
@property (nonatomic) BOOL composeOnOpen;
@property (nonatomic) BOOL callOnOpen;
@property (nonatomic) BOOL peek;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) TSMessagesManager *messagesManager;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OutboundCallInitiator *outboundCallInitiator;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;

@property (nonatomic) NSCache *messageAdapterCache;
@property (nonatomic) BOOL userHasScrolled;

@end

@implementation MessagesViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    [self commonInit];
    
    return self;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) {
        return self;
    }
    
    [self commonInit];
    
    return self;
}

- (void)commonInit
{
    _contactsManager = [Environment getCurrent].contactsManager;
    _contactsUpdater = [Environment getCurrent].contactsUpdater;
    _messageSender = [Environment getCurrent].messageSender;
    _outboundCallInitiator = [Environment getCurrent].outboundCallInitiator;
    _storageManager = [TSStorageManager sharedManager];
    _messagesManager = [TSMessagesManager sharedManager];
    _networkManager = [TSNetworkManager sharedManager];
    _blockingManager = [OWSBlockingManager sharedManager];

    [self addNotificationListeners];
}

- (void)addNotificationListeners
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockedPhoneNumbersDidChange:)
                                                 name:kNSNotificationName_BlockedPhoneNumbersDidChange
                                               object:nil];
}

- (void)blockedPhoneNumbersDidChange:(id)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ensureBlockStateIndicator];
    });
}

- (void)peekSetup {
    _peek = YES;
    [self setComposeOnOpen:NO];
}

- (void)popped {
    _peek = NO;
    [self hideInputIfNeeded];
}

- (void)configureForThread:(TSThread *)thread
    keyboardOnViewAppearing:(BOOL)keyboardOnViewAppearing
        callOnViewAppearing:(BOOL)callOnViewAppearing
{
    if (callOnViewAppearing) {
        keyboardOnViewAppearing = NO;
    }

    _thread = thread;
    isGroupConversation = [self.thread isKindOfClass:[TSGroupThread class]];
    _composeOnOpen = keyboardOnViewAppearing;
    _callOnOpen = callOnViewAppearing;

    [self markAllMessagesAsRead];

    [self.uiDatabaseConnection beginLongLivedReadTransaction];
    self.messageMappings =
        [[YapDatabaseViewMappings alloc] initWithGroups:@[ thread.uniqueId ] view:TSMessageDatabaseViewExtensionName];
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      [self.messageMappings updateWithTransaction:transaction];
      self.page = 0;
      [self updateRangeOptionsForPage:self.page];
      [self.collectionView reloadData];
    }];
    [self updateLoadEarlierVisible];
}

- (BOOL)userLeftGroup
{
    if (![_thread isKindOfClass:[TSGroupThread class]]) {
        return NO;
    }

    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    return ![groupThread.groupModel.groupMemberIds containsObject:[TSAccountManager localNumber]];
}

- (void)hideInputIfNeeded {
    if (_peek) {
        [self inputToolbar].hidden = YES;
        [self.inputToolbar endEditing:TRUE];
        return;
    }

    if (self.userLeftGroup) {
        [self inputToolbar].hidden = YES; // user has requested they leave the group. further sends disallowed
        [self.inputToolbar endEditing:TRUE];
    } else {
        [self inputToolbar].hidden = NO;
        [self loadDraftInCompose];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self.navigationController.navigationBar setTranslucent:NO];

    self.messageAdapterCache = [[NSCache alloc] init];

    _attachButton = [[UIButton alloc] init];
    _attachButton.accessibilityLabel = NSLocalizedString(@"ATTACHMENT_LABEL", @"Accessibility label for attaching photos");
    _attachButton.accessibilityHint = NSLocalizedString(@"ATTACHMENT_HINT", @"Accessibility hint describing what you can do with the attachment button");
    [_attachButton setFrame:CGRectMake(0,
                                       0,
                                       JSQ_TOOLBAR_ICON_WIDTH + JSQ_IMAGE_INSET * 2,
                                       JSQ_TOOLBAR_ICON_HEIGHT + JSQ_IMAGE_INSET * 2)];
    _attachButton.imageEdgeInsets =
        UIEdgeInsetsMake(JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET);
    [_attachButton setImage:[UIImage imageNamed:@"btnAttachments--blue"] forState:UIControlStateNormal];

    [self initializeTextView];

    [JSQMessagesCollectionViewCell registerMenuAction:@selector(delete:)];
    SEL saveSelector = NSSelectorFromString(@"save:");
    [JSQMessagesCollectionViewCell registerMenuAction:saveSelector];
    SEL shareSelector = NSSelectorFromString(@"share:");
    [JSQMessagesCollectionViewCell registerMenuAction:shareSelector];

    [self initializeCollectionViewLayout];
    [self registerCustomMessageNibs];

    self.senderId          = ME_MESSAGE_IDENTIFIER;
    self.senderDisplayName = ME_MESSAGE_IDENTIFIER;

    [self initializeToolbars];

    if ([self.thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *contactThread = (TSContactThread *)self.thread;
        [ThreadUtil createBlockOfferIfNecessary:contactThread
                                 storageManager:self.storageManager
                                contactsManager:self.contactsManager
                                blockingManager:self.blockingManager];
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    // JSQMVC width is initially 375px on iphone6/ios9 (as specified by the xib), which causes
    // our initial bubble calculations to be off since they happen before the containing
    // view is layed out. https://github.com/jessesquires/JSQMessagesViewController/issues/1257
    if (CGRectGetWidth(self.collectionView.frame) != self.previousCollectionViewFrameWidth) {
        // save frame value from next comparison
        self.previousCollectionViewFrameWidth = CGRectGetWidth(self.collectionView.frame);

        // invalidate layout
        [self.collectionView.collectionViewLayout
            invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
    }
}

- (void)registerCustomMessageNibs
{
    [self.collectionView registerNib:[OWSCallCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSCallCollectionViewCell cellReuseIdentifier]];

    [self.collectionView registerNib:[OWSDisplayedMessageCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSDisplayedMessageCollectionViewCell cellReuseIdentifier]];

    self.outgoingCellIdentifier = [OWSOutgoingMessageCollectionViewCell cellReuseIdentifier];
    [self.collectionView registerNib:[OWSOutgoingMessageCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSOutgoingMessageCollectionViewCell cellReuseIdentifier]];

    self.outgoingMediaCellIdentifier = [OWSOutgoingMessageCollectionViewCell mediaCellReuseIdentifier];
    [self.collectionView registerNib:[OWSOutgoingMessageCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSOutgoingMessageCollectionViewCell mediaCellReuseIdentifier]];

    self.incomingCellIdentifier = [OWSIncomingMessageCollectionViewCell cellReuseIdentifier];
    [self.collectionView registerNib:[OWSIncomingMessageCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSIncomingMessageCollectionViewCell cellReuseIdentifier]];

    self.incomingMediaCellIdentifier = [OWSIncomingMessageCollectionViewCell mediaCellReuseIdentifier];
    [self.collectionView registerNib:[OWSIncomingMessageCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSIncomingMessageCollectionViewCell mediaCellReuseIdentifier]];
}

- (void)toggleObservers:(BOOL)shouldObserve
{
    if (shouldObserve) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didChangePreferredContentSize:)
                                                     name:UIContentSizeCategoryDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yapDatabaseModified:)
                                                     name:YapDatabaseModifiedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(startReadTimer)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(startExpirationTimerAnimations)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(resetContentAndLayout)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillResignActive:)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cancelReadTimer)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                     name:UIContentSizeCategoryDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                     name:YapDatabaseModifiedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:UIApplicationWillResignActiveNotification
                                                      object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:UIApplicationDidEnterBackgroundNotification
                                                      object:nil];
    }
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    [self cancelVoiceMemo];
}

- (void)initializeTextView {
    [self.inputToolbar.contentView.textView setFont:[UIFont ows_dynamicTypeBodyFont]];

    self.inputToolbar.contentView.leftBarButtonItem = self.attachButton;

    UILabel *sendLabel = self.inputToolbar.contentView.rightBarButtonItem.titleLabel;
    // override superclass translations since we support more translations than upstream.
    sendLabel.text = NSLocalizedString(@"SEND_BUTTON_TITLE", nil);
    sendLabel.font = [UIFont ows_regularFontWithSize:17.0f];
    sendLabel.textColor = [UIColor ows_materialBlueColor];
    sendLabel.textAlignment = NSTextAlignmentCenter;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    // Since we're using a custom back button, we have to do some extra work to manage the interactivePopGestureRecognizer
    self.navigationController.interactivePopGestureRecognizer.delegate = self;

    // We need to recheck on every appearance, since the user may have left the group in the settings VC,
    // or on another device.
    [self hideInputIfNeeded];

    [self toggleObservers:YES];

    // Triggering modified notification renders "call notification" when leaving full screen call view
    [self.thread touch];

    // restart any animations that were stopped e.g. while inspecting the contact info screens.
    [self startExpirationTimerAnimations];

    // We should have already requested contact access at this point, so this should be a no-op
    // unless it ever becomes possible to to load this VC without going via the SignalsViewController
    [self.contactsManager requestSystemContactsOnce];

    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
    [self setBarButtonItemsForDisappearingMessagesConfiguration:configuration];
    [self setNavigationTitle];

    NSInteger numberOfMessages = (NSInteger)[self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];
    if (numberOfMessages > 0) {
        NSIndexPath *lastCellIndexPath = [NSIndexPath indexPathForRow:numberOfMessages - 1 inSection:0];
        [self.collectionView scrollToItemAtIndexPath:lastCellIndexPath
                                    atScrollPosition:UICollectionViewScrollPositionBottom
                                            animated:NO];
    }

    // Other views might change these custom menu items, so we
    // need to set them every time we enter this view.
    SEL saveSelector = NSSelectorFromString(@"save:");
    SEL shareSelector = NSSelectorFromString(@"share:");
    [UIMenuController sharedMenuController].menuItems = @[
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SAVE_ACTION",
                                              @"Short name for edit menu item to save contents of media message.")
                                   action:saveSelector],
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SHARE_ACTION",
                                              @"Short name for edit menu item to share contents of media message.")
                                   action:shareSelector],
    ];

    [self ensureBlockStateIndicator];

    [self resetContentAndLayout];

    [((OWSMessagesToolbarContentView *)self.inputToolbar.contentView)ensureSubviews];
}

- (void)resetContentAndLayout
{
    // Avoid layout corrupt issues and out-of-date message subtitles.
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
}

- (void)setUserHasScrolled:(BOOL)userHasScrolled {
    _userHasScrolled = userHasScrolled;
    
    [self ensureBlockStateIndicator];
}

- (void)ensureBlockStateIndicator
{
    // This method should be called rarely, so it's simplest to discard and
    // rebuild the indicator view every time.
    [self.blockStateIndicator removeFromSuperview];
    self.blockStateIndicator = nil;
    
    if (self.userHasScrolled) {
        return;
    }

    NSString *blockStateMessage = nil;
    if ([self isBlockedContactConversation]) {
        blockStateMessage = NSLocalizedString(@"MESSAGES_VIEW_CONTACT_BLOCKED",
                                              @"Indicates that this 1:1 conversation has been blocked.");
    } else if (isGroupConversation) {
        int blockedGroupMemberCount = [self blockedGroupMemberCount];
        if (blockedGroupMemberCount == 1) {
            blockStateMessage = NSLocalizedString(@"MESSAGES_VIEW_GROUP_1_MEMBER_BLOCKED",
                                                  @"Indicates that a single member of this group has been blocked.");
        } else if (blockedGroupMemberCount > 1) {
            blockStateMessage = [NSString stringWithFormat:NSLocalizedString(@"MESSAGES_VIEW_GROUP_N_MEMBERS_BLOCKED_FORMAT",
                                                                             @"Indicates that some members of this group has been blocked. Embeds "
                                                                             @"{{the number of blocked users in this group}}."),
                                 blockedGroupMemberCount];
        }
    }
    
    if (blockStateMessage) {
        UILabel *label = [UILabel new];
        label.font = [UIFont ows_mediumFontWithSize:14.f];
        label.text = blockStateMessage;
        label.textColor = [UIColor whiteColor];
        
        UIView * blockStateIndicator = [UIView new];
        blockStateIndicator.backgroundColor = [UIColor ows_redColor];
        blockStateIndicator.layer.cornerRadius = 2.5f;
        
        // Use a shadow to "pop" the indicator above the other views.
        blockStateIndicator.layer.shadowColor = [UIColor blackColor].CGColor;
        blockStateIndicator.layer.shadowOffset = CGSizeMake(2, 3);
        blockStateIndicator.layer.shadowRadius = 2.f;
        blockStateIndicator.layer.shadowOpacity = 0.35f;
        
        [blockStateIndicator addSubview:label];
        [label autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:5];
        [label autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:5];
        [label autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:15];
        [label autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:15];
        
        [blockStateIndicator addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                          action:@selector(blockStateIndicatorWasTapped:)]];
        
        [self.view addSubview:blockStateIndicator];
        [blockStateIndicator autoHCenterInSuperview];
        [blockStateIndicator autoPinToTopLayoutGuideOfViewController:self withInset:10];
        [self.view layoutSubviews];
        
        self.blockStateIndicator = blockStateIndicator;
    }
}
         
- (void)blockStateIndicatorWasTapped:(UIGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateRecognized) {
        return;
    }

    if ([self isBlockedContactConversation]) {
        // If this a blocked 1:1 conversation, offer to unblock the user.
        [self showUnblockContactUI:nil];
    } else if (isGroupConversation) {
        // If this a group conversation with at least one blocked member,
        // Show the block list view.
        int blockedGroupMemberCount = [self blockedGroupMemberCount];
        if (blockedGroupMemberCount > 0) {
            BlockListViewController *vc = [[BlockListViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        }
    }
}

- (void)showUnblockContactUI:(BlockActionCompletionBlock)completionBlock
{
    OWSAssert([self.thread isKindOfClass:[TSContactThread class]]);

    self.userHasScrolled = NO;
    
    // To avoid "noisy" animations (hiding the keyboard before showing
    // the action sheet, re-showing it after), hide the keyboard before
    // showing the "unblock" action sheet.
    //
    // Unblocking is a rare interaction, so it's okay to leave the keyboard
    // hidden.
    [self dismissKeyBoard];

    NSString *contactIdentifier = ((TSContactThread *)self.thread).contactIdentifier;
    [BlockListUIUtils showUnblockPhoneNumberActionSheet:contactIdentifier
                                     fromViewController:self
                                        blockingManager:_blockingManager
                                        contactsManager:_contactsManager
                                        completionBlock:completionBlock];
}

- (BOOL)isBlockedContactConversation
{
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        return NO;
    }
    NSString *contactIdentifier = ((TSContactThread *)self.thread).contactIdentifier;
    return [[_blockingManager blockedPhoneNumbers] containsObject:contactIdentifier];
}

- (int)blockedGroupMemberCount
{
    OWSAssert(isGroupConversation);
    OWSAssert([self.thread isKindOfClass:[TSGroupThread class]]);
    
    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    int blockedMemberCount = 0;
    NSArray<NSString *> *blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];
    for (NSString *contactIdentifier in groupThread.groupModel.groupMemberIds) {
        if ([blockedPhoneNumbers containsObject:contactIdentifier]) {
            blockedMemberCount++;
        }
    }
    return blockedMemberCount;
}

- (void)startReadTimer {
    self.readTimer = [NSTimer scheduledTimerWithTimeInterval:1
                                                      target:self
                                                    selector:@selector(markAllMessagesAsRead)
                                                    userInfo:nil
                                                     repeats:YES];
}

- (void)cancelReadTimer {
    [self.readTimer invalidate];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self dismissKeyBoard];
    [self startReadTimer];

    [self updateBackButtonUnreadCount];

    [self.inputToolbar.contentView.textView endEditing:YES];

    self.inputToolbar.contentView.textView.editable = YES;
    if (_composeOnOpen && !self.inputToolbar.hidden) {
        [self popKeyBoard];
        _composeOnOpen = NO;
    }
    if (_callOnOpen) {
        [self callAction:nil];
        _callOnOpen = NO;
    }
    [self updateNavigationBarSubtitleLabel];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self toggleObservers:NO];

    // Since we're using a custom back button, we have to do some extra work to manage the interactivePopGestureRecognizer
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;

    [self.audioAttachmentPlayer stop];
    self.audioAttachmentPlayer = nil;

    [self cancelReadTimer];
    [self saveDraft];

    [self cancelVoiceMemo];
}

- (void)startExpirationTimerAnimations
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OWSMessagesViewControllerDidAppearNotification
                                                        object:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.inputToolbar.contentView.textView.editable = NO;
    self.userHasScrolled = NO;
}

#pragma mark - Initiliazers

- (void)setNavigationTitle
{
    NSString *navTitle = self.thread.name;
    if (isGroupConversation && [navTitle length] == 0) {
        navTitle = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
    }
    self.title = nil;

    if ([navTitle isEqualToString:self.navigationBarTitleLabel.text]) {
        return;
    }
    
    self.navigationBarTitleLabel.text = navTitle;

    // Changing the title requires relayout of the nav bar contents.
    OWSDisappearingMessagesConfiguration *configuration =
    [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
    [self setBarButtonItemsForDisappearingMessagesConfiguration:configuration];
}

- (void)setBarButtonItemsForDisappearingMessagesConfiguration:
    (OWSDisappearingMessagesConfiguration *)disappearingMessagesConfiguration
{
    UIBarButtonItem *backItem = [self createOWSBackButton];
    const CGFloat unreadCountViewDiameter = 16;
    if (_backButtonUnreadCountView == nil) {
        _backButtonUnreadCountView = [UIView new];
        _backButtonUnreadCountView.layer.cornerRadius = unreadCountViewDiameter / 2;
        _backButtonUnreadCountView.backgroundColor = [UIColor redColor];
        _backButtonUnreadCountView.hidden = YES;
        _backButtonUnreadCountView.userInteractionEnabled = NO;

        _backButtonUnreadCountLabel = [UILabel new];
        _backButtonUnreadCountLabel.backgroundColor = [UIColor clearColor];
        _backButtonUnreadCountLabel.textColor = [UIColor whiteColor];
        _backButtonUnreadCountLabel.font = [UIFont systemFontOfSize:11];
        _backButtonUnreadCountLabel.textAlignment = NSTextAlignmentCenter;
    }
    // This method gets called multiple times, so it's important we re-layout the unread badge
    // with respect to the new backItem.
    [backItem.customView addSubview:_backButtonUnreadCountView];
    [_backButtonUnreadCountView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:-6];
    [_backButtonUnreadCountView autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:1];
    [_backButtonUnreadCountView autoSetDimension:ALDimensionHeight toSize:unreadCountViewDiameter];
    // We set a min width, but we will also pin to our subview label, so we can grow to accommodate multiple digits.
    [_backButtonUnreadCountView autoSetDimension:ALDimensionWidth
                                          toSize:unreadCountViewDiameter
                                        relation:NSLayoutRelationGreaterThanOrEqual];

    [_backButtonUnreadCountView addSubview:_backButtonUnreadCountLabel];
    [_backButtonUnreadCountLabel autoPinWidthToSuperviewWithMargin:4];
    [_backButtonUnreadCountLabel autoPinHeightToSuperview];

    // Initialize newly created unread count badge to accurately reflect the current unread count.
    [self updateBackButtonUnreadCount];


    const CGFloat kTitleVSpacing = 0.f;
    if (!self.navigationBarTitleView) {
        self.navigationBarTitleView = [UIView new];
        [self.navigationBarTitleView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                                  action:@selector(navigationTitleTapped:)]];
#ifdef DEBUG
        [self.navigationBarTitleView addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                                        action:@selector(navigationTitleLongPressed:)]];
#endif
        
        self.navigationBarTitleLabel = [UILabel new];
        self.navigationBarTitleLabel.textColor = [UIColor whiteColor];
        self.navigationBarTitleLabel.font = [UIFont ows_boldFontWithSize:18.f];
        self.navigationBarTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.navigationBarTitleView addSubview:self.navigationBarTitleLabel];
        
        self.navigationBarSubtitleLabel = [UILabel new];
        [self updateNavigationBarSubtitleLabel];
        [self.navigationBarTitleView addSubview:self.navigationBarSubtitleLabel];
    }
    
    // We need to manually resize and position the title views;
    // iOS AutoLayout doesn't work inside navigation bar items.
    [self.navigationBarTitleLabel sizeToFit];
    [self.navigationBarSubtitleLabel sizeToFit];
    const CGFloat kShortScreenDimension = MIN([UIScreen mainScreen].bounds.size.width,
                                              [UIScreen mainScreen].bounds.size.height);
    // We want to leave space for the "back" button, the "timer" button, and the "call"
    // button, and all of the whitespace around these views.  There
    // isn't a convenient way to calculate these in a navigation bar, so we just leave
    // a constant amount of space which will be safe unless Apple makes radical changes
    // to the appearance of the navigation bar.
    int rightBarButtonItemCount = 0;
    if ([self canCall]) {
        rightBarButtonItemCount++;
    }
    if (disappearingMessagesConfiguration.isEnabled) {
        rightBarButtonItemCount++;
    }
    CGFloat barButtonSize = 0;
    switch (rightBarButtonItemCount) {
        case 0:
            barButtonSize = 70;
            break;
        case 1:
            barButtonSize = 105;
            break;
        default:
            OWSAssert(0);
            // In production, fall through to the largest defined case.
        case 2:
            barButtonSize = 150;
            break;
    }
    CGFloat maxTitleViewWidth = kShortScreenDimension - barButtonSize;
    const CGFloat titleViewWidth = MIN(maxTitleViewWidth,
                                       MAX(self.navigationBarTitleLabel.frame.size.width,
                                           self.navigationBarSubtitleLabel.frame.size.width));
    self.navigationBarTitleView.frame = CGRectMake(0, 0,
                                                   titleViewWidth,
                                                   self.navigationBarTitleLabel.frame.size.height +
                                                   self.navigationBarSubtitleLabel.frame.size.height +
                                                   kTitleVSpacing);
    self.navigationBarTitleLabel.frame = CGRectMake(0,
                                                    0,
                                                    titleViewWidth,
                                                    self.navigationBarTitleLabel.frame.size.height);
    self.navigationBarSubtitleLabel.frame = CGRectMake(0,
                                                       self.navigationBarTitleView.frame.size.height - self.navigationBarSubtitleLabel.frame.size.height,
                                                       titleViewWidth,
                                                       self.navigationBarSubtitleLabel.frame.size.height);
    
    self.navigationItem.leftBarButtonItems = @[
                                               backItem,
                                               [[UIBarButtonItem alloc] initWithCustomView:self.navigationBarTitleView],
                                               ];

    if (self.userLeftGroup) {
        self.navigationItem.rightBarButtonItems = @[];
        return;
    }

    const CGFloat kBarButtonSize = 44;
    NSMutableArray<UIBarButtonItem *> *barButtons = [NSMutableArray new];
    if ([self canCall]) {
        // We use UIButtons with [UIBarButtonItem initWithCustomView:...] instead of
        // UIBarButtonItem in order to ensure that these buttons are spaced tightly.
        // The contents of the navigation bar are cramped in this view.
        UIButton *callButton = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImage *image = [UIImage imageNamed:@"button_phone_white"];
        [callButton setImage:image
                    forState:UIControlStateNormal];
        UIEdgeInsets imageEdgeInsets = UIEdgeInsetsZero;
        // We normally would want to use left and right insets that ensure the button
        // is square and the icon is centered.  However UINavigationBar doesn't offer us
        // control over the margins and spacing of its content, and the buttons end up
        // too far apart and too far from the edge of the screen. So we use a smaller
        // right inset tighten up the layout.
        imageEdgeInsets.left = round((kBarButtonSize - image.size.width) * 0.5f);
        imageEdgeInsets.right = round((kBarButtonSize - (image.size.width + imageEdgeInsets.left)) * 0.5f);
        imageEdgeInsets.top = round((kBarButtonSize - image.size.height) * 0.5f);
        imageEdgeInsets.bottom = round(kBarButtonSize - (image.size.height + imageEdgeInsets.top));
        callButton.imageEdgeInsets = imageEdgeInsets;
        callButton.accessibilityLabel = NSLocalizedString(@"CALL_LABEL", "Accessibilty label for placing call button");
        [callButton addTarget:self
                       action:@selector(callAction:)
             forControlEvents:UIControlEventTouchUpInside];
        callButton.frame = CGRectMake(0, 0,
                                      round(image.size.width + imageEdgeInsets.left + imageEdgeInsets.right),
                                      round(image.size.height + imageEdgeInsets.top + imageEdgeInsets.bottom));
        [barButtons addObject:[[UIBarButtonItem alloc] initWithCustomView:callButton]];
    }

    if (disappearingMessagesConfiguration.isEnabled) {
        UIButton *timerButton = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImage *image = [UIImage imageNamed:@"button_timer_white"];
        [timerButton setImage:image
                    forState:UIControlStateNormal];
        UIEdgeInsets imageEdgeInsets = UIEdgeInsetsZero;
        // We normally would want to use left and right insets that ensure the button
        // is square and the icon is centered.  However UINavigationBar doesn't offer us
        // control over the margins and spacing of its content, and the buttons end up
        // too far apart and too far from the edge of the screen. So we use a smaller
        // right inset tighten up the layout.
        imageEdgeInsets.left = round((kBarButtonSize - image.size.width) * 0.5f);
        imageEdgeInsets.right = round((kBarButtonSize - (image.size.width + imageEdgeInsets.left)) * 0.5f);
        imageEdgeInsets.top = round((kBarButtonSize - image.size.height) * 0.5f);
        imageEdgeInsets.bottom = round(kBarButtonSize - (image.size.height + imageEdgeInsets.top));
        timerButton.imageEdgeInsets = imageEdgeInsets;
        timerButton.accessibilityLabel = NSLocalizedString(@"DISAPPEARING_MESSAGES_LABEL", @"Accessibility label for disappearing messages");
        NSString *formatString = NSLocalizedString(@"DISAPPEARING_MESSAGES_HINT", @"Accessibility hint that contains current timeout information");
        timerButton.accessibilityHint = [NSString stringWithFormat:formatString, [disappearingMessagesConfiguration durationString]];
        [timerButton addTarget:self
                        action:@selector(didTapTimerInNavbar:)
              forControlEvents:UIControlEventTouchUpInside];
        timerButton.frame = CGRectMake(0, 0,
                                       round(image.size.width + imageEdgeInsets.left + imageEdgeInsets.right),
                                       round(image.size.height + imageEdgeInsets.top + imageEdgeInsets.bottom));
        [barButtons addObject:[[UIBarButtonItem alloc] initWithCustomView:timerButton]];
    }
    
    self.navigationItem.rightBarButtonItems = [barButtons copy];
}

- (void)updateNavigationBarSubtitleLabel
{
    NSMutableAttributedString *subtitleText = [NSMutableAttributedString new];
    if (self.thread.isMuted) {
        // Show a "mute" icon before the navigation bar subtitle if this thread is muted.
        [subtitleText
            appendAttributedString:[[NSAttributedString alloc]
                                       initWithString:@"\ue067  "
                                           attributes:@{
                                               NSFontAttributeName : [UIFont ows_elegantIconsFont:7.f],
                                               NSForegroundColorAttributeName : [UIColor colorWithWhite:0.9f alpha:1.f],
                                           }]];
    }
    [subtitleText
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:NSLocalizedString(@"MESSAGES_VIEW_TITLE_SUBTITLE",
                                                      @"The subtitle for the messages view title indicates that the "
                                                      @"title can be tapped to access settings for this conversation.")
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_regularFontWithSize:9.f],
                                           NSForegroundColorAttributeName : [UIColor colorWithWhite:0.9f alpha:1.f],
                                       }]];
    self.navigationBarSubtitleLabel.attributedText = subtitleText;
    [self.navigationBarSubtitleLabel sizeToFit];
}

- (void)initializeToolbars
{
    // HACK JSQMessagesViewController doesn't yet support dynamic type in the inputToolbar.
    // See: https://github.com/jessesquires/JSQMessagesViewController/pull/1169/files
    [self.inputToolbar.contentView.textView sizeToFit];
    self.inputToolbar.preferredDefaultHeight = self.inputToolbar.contentView.textView.frame.size.height + 16;

    // prevent draft from obscuring message history in case user wants to scroll back to refer to something
    // while composing a long message.
    self.inputToolbar.maximumHeight = 300;
    
    OWSAssert(self.inputToolbar.contentView);
    OWSAssert(self.inputToolbar.contentView.textView);
    self.inputToolbar.contentView.textView.pasteDelegate = self;
    ((OWSMessagesComposerTextView *) self.inputToolbar.contentView.textView).textViewPasteDelegate = self;
    ((OWSMessagesToolbarContentView *)self.inputToolbar.contentView).delegate = self;
}

// Overiding JSQMVC layout defaults
- (void)initializeCollectionViewLayout
{
    [self.collectionView.collectionViewLayout setMessageBubbleFont:[UIFont ows_dynamicTypeBodyFont]];

    self.collectionView.showsVerticalScrollIndicator = NO;
    self.collectionView.showsHorizontalScrollIndicator = NO;

    [self updateLoadEarlierVisible];

    self.collectionView.collectionViewLayout.incomingAvatarViewSize = CGSizeZero;
    self.collectionView.collectionViewLayout.outgoingAvatarViewSize = CGSizeZero;

    if ([UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPad) {
        // Narrow the bubbles a bit to create more white space in the messages view
        // Since we're not using avatars it gets a bit crowded otherwise.
        self.collectionView.collectionViewLayout.messageBubbleLeftRightMargin = 80.0f;
    }

    // Bubbles
    self.collectionView.collectionViewLayout.bubbleSizeCalculator = [[OWSMessagesBubblesSizeCalculator alloc] init];
    JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] init];
    self.incomingBubbleImageData = [bubbleFactory incomingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleLightGrayColor]];
    self.outgoingBubbleImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor ows_materialBlueColor]];
    self.currentlyOutgoingBubbleImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor ows_fadedBlueColor]];
    self.outgoingMessageFailedImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor grayColor]];

}

#pragma mark - Fingerprints

- (void)showFingerprintWithTheirIdentityKey:(NSData *)theirIdentityKey theirSignalId:(NSString *)theirSignalId
{
    // Ensure keyboard isn't hiding the "safety numbers changed" interaction when we
    // return from FingerprintViewController.
    [self dismissKeyBoard];

    OWSFingerprintBuilder *builder =
        [[OWSFingerprintBuilder alloc] initWithStorageManager:self.storageManager contactsManager:self.contactsManager];
    OWSFingerprint *fingerprint =
        [builder fingerprintWithTheirSignalId:theirSignalId theirIdentityKey:theirIdentityKey];
    [self markAllMessagesAsRead];

    NSString *contactName = [self.contactsManager displayNameForPhoneIdentifier:theirSignalId];

    UIViewController *viewController =
        [[UIStoryboard main] instantiateViewControllerWithIdentifier:@"FingerprintViewController"];
    if (![viewController isKindOfClass:[FingerprintViewController class]]) {
        OWSAssert(NO);
        DDLogError(@"%@ expecting fingerprint view controller, but got: %@", self.tag, viewController);
        return;
    }
    FingerprintViewController *fingerprintViewController = (FingerprintViewController *)viewController;

    [fingerprintViewController configureWithThread:self.thread fingerprint:fingerprint contactName:contactName];
    [self presentViewController:fingerprintViewController animated:YES completion:nil];
}

#pragma mark - Calls

- (void)callAction:(id)sender {
    OWSAssert([self.thread isKindOfClass:[TSContactThread class]]);

    if (![self canCall]) {
        DDLogWarn(@"Tried to initiate a call but thread is not callable.");
        return;
    }

    if ([self isBlockedContactConversation]) {
        __weak MessagesViewController *weakSelf = self;
        [self showUnblockContactUI:^(BOOL isBlocked) {
            if (!isBlocked) {
                [weakSelf callAction:nil];
            }
        }];
        return;
    }

    [self.outboundCallInitiator initiateCallWithRecipientId:self.thread.contactIdentifier];
}

- (BOOL)canCall {
    return !(isGroupConversation || [((TSContactThread *)self.thread).contactIdentifier isEqualToString:[TSAccountManager localNumber]]);
}

#pragma mark - JSQMessagesViewController method overrides

- (void)didPressSendButton:(UIButton *)button
           withMessageText:(NSString *)text
                  senderId:(NSString *)senderId
         senderDisplayName:(NSString *)senderDisplayName
                      date:(NSDate *)date
{
    [self didPressSendButton:button
             withMessageText:text
                    senderId:senderId
           senderDisplayName:senderDisplayName
                        date:date
         updateKeyboardState:YES];
}

- (void)didPressSendButton:(UIButton *)button
           withMessageText:(NSString *)text
                  senderId:(NSString *)senderId
         senderDisplayName:(NSString *)senderDisplayName
                      date:(NSDate *)date
       updateKeyboardState:(BOOL)updateKeyboardState
{
    if ([self isBlockedContactConversation]) {
        __weak MessagesViewController *weakSelf = self;
        [self showUnblockContactUI:^(BOOL isBlocked) {
            if (!isBlocked) {
                [weakSelf didPressSendButton:button
                             withMessageText:text
                                    senderId:senderId
                           senderDisplayName:senderDisplayName
                                        date:date
                         updateKeyboardState:NO];
            }
        }];
        return;
    }

    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    if (text.length > 0) {
        if ([Environment.preferences soundInForeground]) {
            [JSQSystemSoundPlayer jsq_playMessageSentSound];
        }
        // Limit outgoing text messages to 16kb.
        //
        // We convert large text messages to attachments
        // which are presented as normal text messages.
        const NSUInteger kOversizeTextMessageSizeThreshold = 16 * 1024;
        if ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= kOversizeTextMessageSizeThreshold) {
            SignalAttachment *attachment =
                [SignalAttachment attachmentWithData:[text dataUsingEncoding:NSUTF8StringEncoding]
                                             dataUTI:SignalAttachment.kOversizeTextAttachmentUTI
                                            filename:nil];
            [ThreadUtil sendMessageWithAttachment:attachment inThread:self.thread messageSender:self.messageSender];
        } else {
            [ThreadUtil sendMessageWithText:text inThread:self.thread messageSender:self.messageSender];
        }
        if (updateKeyboardState)
        {
            [self toggleDefaultKeyboard];
        }
        [self clearDraft];
        [self finishSendingMessage];
        [((OWSMessagesToolbarContentView *)self.inputToolbar.contentView)ensureSubviews];
    }
}

- (void)toggleDefaultKeyboard
{
    // Primary language is nil for the emoji keyboard & we want to stay on it after sending
    if (![self.inputToolbar.contentView.textView.textInputMode primaryLanguage]) {
        return;
    }
    [self.keyboardController endListeningForKeyboard];
    [self dismissKeyBoard];
    [self popKeyBoard];
    [self.keyboardController beginListeningForKeyboard];
}

#pragma mark - UICollectionViewDelegate

// Override JSQMVC
- (BOOL)collectionView:(JSQMessagesCollectionView *)collectionView shouldShowMenuForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath == nil) {
        DDLogError(@"Aborting shouldShowMenuForItemAtIndexPath because indexPath is nil");
        // Not sure why this is nil, but occasionally it is, which crashes.
        return NO;
    }

    // JSQM does some setup in super method
    [super collectionView:collectionView shouldShowMenuForItemAtIndexPath:indexPath];


    // Don't show menu for in-progress downloads.
    // We don't want to give the user the wrong idea that deleting would "cancel" the download.
    id<OWSMessageData> message = [self messageAtIndexPath:indexPath];
    if (message.isMediaMessage && [message.media isKindOfClass:[AttachmentPointerAdapter class]]) {
        AttachmentPointerAdapter *attachmentPointerAdapter = (AttachmentPointerAdapter *)message.media;
        return attachmentPointerAdapter.attachmentPointer.state == TSAttachmentPointerStateFailed;
    }

    // Super method returns false for media methods. We want menu for *all* items
    return YES;
}

- (void)collectionView:(UICollectionView *)collectionView
       willDisplayCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([cell conformsToProtocol:@protocol(OWSMessageCollectionViewCell)]) {
        [((id<OWSMessageCollectionViewCell>)cell) setCellVisible:YES];
    }
}

- (void)collectionView:(UICollectionView *)collectionView
    didEndDisplayingCell:(nonnull UICollectionViewCell *)cell
      forItemAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    if ([cell conformsToProtocol:@protocol(OWSExpirableMessageView)]) {
        id<OWSExpirableMessageView> expirableView = (id<OWSExpirableMessageView>)cell;
        [expirableView stopExpirationTimer];
    }

    if ([cell conformsToProtocol:@protocol(OWSMessageCollectionViewCell)]) {
        [((id<OWSMessageCollectionViewCell>)cell) setCellVisible:NO];
    }
}

#pragma mark - JSQMessages CollectionView DataSource

- (id<OWSMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView
       messageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [self messageAtIndexPath:indexPath];
}

- (id<JSQMessageBubbleImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView
             messageBubbleImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    TSInteraction *message = [self interactionAtIndexPath:indexPath];

    if ([message isKindOfClass:[TSOutgoingMessage class]]) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)message;
        switch (outgoingMessage.messageState) {
            case TSOutgoingMessageStateUnsent:
                return self.outgoingMessageFailedImageData;
            case TSOutgoingMessageStateAttemptingOut:
                return self.currentlyOutgoingBubbleImageData;
            case TSOutgoingMessageStateSent_OBSOLETE:
            case TSOutgoingMessageStateDelivered_OBSOLETE:
                OWSAssert(0);
                return self.outgoingBubbleImageData;
            case TSOutgoingMessageStateSentToService:
                return self.outgoingBubbleImageData;
        }
    }

    return self.incomingBubbleImageData;
}

- (id<JSQMessageAvatarImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView
                    avatarImageDataForItemAtIndexPath:(NSIndexPath *)indexPath {
    return nil;
}

#pragma mark - UICollectionView DataSource

- (UICollectionViewCell *)collectionView:(JSQMessagesCollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    id<OWSMessageData> message = [self messageAtIndexPath:indexPath];
    NSParameterAssert(message != nil);

    JSQMessagesCollectionViewCell *cell;
    switch (message.messageType) {
        case TSCallAdapter: {
            OWSCall *call = (OWSCall *)message;
            cell = [self loadCallCellForCall:call atIndexPath:indexPath];
        } break;
        case TSInfoMessageAdapter: {
            cell = [self loadInfoMessageCellForMessage:(TSMessageAdapter *)message atIndexPath:indexPath];
        } break;
        case TSErrorMessageAdapter: {
            cell = [self loadErrorMessageCellForMessage:(TSMessageAdapter *)message atIndexPath:indexPath];
        } break;
        case TSIncomingMessageAdapter: {
            cell = [self loadIncomingMessageCellForMessage:message atIndexPath:indexPath];
        } break;
        case TSOutgoingMessageAdapter: {
            cell = [self loadOutgoingCellForMessage:message atIndexPath:indexPath];
        } break;
        default: {
            DDLogWarn(@"using default cell constructor for message: %@", message);
            cell = (JSQMessagesCollectionViewCell *)[super collectionView:collectionView cellForItemAtIndexPath:indexPath];
        } break;
    }
    cell.delegate = collectionView;

    if (message.shouldStartExpireTimer && [cell conformsToProtocol:@protocol(OWSExpirableMessageView)]) {
        id<OWSExpirableMessageView> expirableView = (id<OWSExpirableMessageView>)cell;
        [expirableView startExpirationTimerWithExpiresAtSeconds:message.expiresAtSeconds
                                         initialDurationSeconds:message.expiresInSeconds];
    }

    return cell;
}

#pragma mark - Loading message cells

- (JSQMessagesCollectionViewCell *)loadIncomingMessageCellForMessage:(id<OWSMessageData>)message
                                                         atIndexPath:(NSIndexPath *)indexPath
{
    OWSIncomingMessageCollectionViewCell *cell
        = (OWSIncomingMessageCollectionViewCell *)[super collectionView:self.collectionView
                                                 cellForItemAtIndexPath:indexPath];

    if (![cell isKindOfClass:[OWSIncomingMessageCollectionViewCell class]]) {
        DDLogError(@"%@ Unexpected cell type: %@", self.tag, cell);
        return cell;
    }

    if ([message isMediaMessage] && [[message media] conformsToProtocol:@protocol(OWSMessageMediaAdapter)]) {
        cell.mediaAdapter = (id<OWSMessageMediaAdapter>)[message media];
    }

    [cell ows_didLoad];
    return cell;
}

- (JSQMessagesCollectionViewCell *)loadOutgoingCellForMessage:(id<OWSMessageData>)message
                                                  atIndexPath:(NSIndexPath *)indexPath
{
    OWSOutgoingMessageCollectionViewCell *cell
        = (OWSOutgoingMessageCollectionViewCell *)[super collectionView:self.collectionView
                                                 cellForItemAtIndexPath:indexPath];

    if (![cell isKindOfClass:[OWSOutgoingMessageCollectionViewCell class]]) {
        DDLogError(@"%@ Unexpected cell type: %@", self.tag, cell);
        return cell;
    }

    if ([message isMediaMessage] && [[message media] conformsToProtocol:@protocol(OWSMessageMediaAdapter)]) {
        cell.mediaAdapter = (id<OWSMessageMediaAdapter>)[message media];
    }

    [cell ows_didLoad];

    if (message.isMediaMessage) {
        if (![message isKindOfClass:[TSMessageAdapter class]]) {
            DDLogError(@"%@ Unexpected media message:%@", self.tag, message.class);
        }
        TSMessageAdapter *messageAdapter = (TSMessageAdapter *)message;
        cell.mediaView.alpha = messageAdapter.mediaViewAlpha;
    }

    return cell;
}

- (OWSCallCollectionViewCell *)loadCallCellForCall:(OWSCall *)call atIndexPath:(NSIndexPath *)indexPath
{
    OWSCallCollectionViewCell *callCell = [self.collectionView dequeueReusableCellWithReuseIdentifier:[OWSCallCollectionViewCell cellReuseIdentifier]
                                                                                         forIndexPath:indexPath];

    NSString *text =  call.date != nil ? [call text] : call.senderDisplayName;
    NSString *allText = call.date != nil ? [text stringByAppendingString:[call dateText]] : text;

    UIFont *boldFont = [UIFont fontWithName:@"HelveticaNeue-Medium" size:12.0f];
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:allText
                                                                                       attributes:@{ NSFontAttributeName: boldFont }];
    if([call date]!=nil) {
        // Not a group meta message
        UIFont *regularFont = [UIFont fontWithName:@"HelveticaNeue-Light" size:12.0f];
        const NSRange range = NSMakeRange([text length], [[call dateText] length]);
        [attributedText setAttributes:@{ NSFontAttributeName: regularFont }
                                range:range];
    }
    callCell.textView.text = nil;
    callCell.textView.attributedText = attributedText;

    callCell.textView.textAlignment = NSTextAlignmentCenter;
    callCell.textView.textColor = [UIColor ows_materialBlueColor];
    callCell.layer.shouldRasterize = YES;
    callCell.layer.rasterizationScale = [UIScreen mainScreen].scale;

    // Disable text selectability. Specifying this in prepareForReuse/awakeFromNib was not sufficient.
    callCell.textView.userInteractionEnabled = NO;
    callCell.textView.selectable = NO;

    return callCell;
}

- (OWSDisplayedMessageCollectionViewCell *)loadDisplayedMessageCollectionViewCellForIndexPath:(NSIndexPath *)indexPath
{
    OWSDisplayedMessageCollectionViewCell *messageCell = [self.collectionView dequeueReusableCellWithReuseIdentifier:[OWSDisplayedMessageCollectionViewCell cellReuseIdentifier]
                                                                                                        forIndexPath:indexPath];
    messageCell.layer.shouldRasterize = YES;
    messageCell.layer.rasterizationScale = [UIScreen mainScreen].scale;
    messageCell.textView.textColor = [UIColor darkGrayColor];
    messageCell.cellTopLabel.attributedText = [self.collectionView.dataSource collectionView:self.collectionView attributedTextForCellTopLabelAtIndexPath:indexPath];

    return messageCell;
}

- (OWSDisplayedMessageCollectionViewCell *)loadInfoMessageCellForMessage:(TSMessageAdapter *)infoMessage
                                                             atIndexPath:(NSIndexPath *)indexPath
{
    OWSDisplayedMessageCollectionViewCell *infoCell = [self loadDisplayedMessageCollectionViewCellForIndexPath:indexPath];

    // HACK this will get called when we get a new info message, but there's gotta be a better spot for this.
    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
    [self setBarButtonItemsForDisappearingMessagesConfiguration:configuration];

    infoCell.textView.text = [infoMessage text];

    // Disable text selectability. Specifying this in prepareForReuse/awakeFromNib was not sufficient.
    infoCell.textView.userInteractionEnabled = NO;
    infoCell.textView.selectable = NO;

    infoCell.messageBubbleContainerView.layer.borderColor = [[UIColor ows_infoMessageBorderColor] CGColor];
    if (infoMessage.infoMessageType == TSInfoMessageTypeDisappearingMessagesUpdate) {
        infoCell.headerImageView.image = [UIImage imageNamed:@"ic_timer"];
        infoCell.headerImageView.backgroundColor = [UIColor whiteColor];
        // Lighten up the broad stroke header icon to match the perceived color of the border.
        infoCell.headerImageView.tintColor = [UIColor ows_infoMessageBorderColor];
    } else {
        infoCell.headerImageView.image = [UIImage imageNamed:@"warning_white"];
    }


    return infoCell;
}

- (OWSDisplayedMessageCollectionViewCell *)loadErrorMessageCellForMessage:(TSMessageAdapter *)errorMessage
                                                              atIndexPath:(NSIndexPath *)indexPath
{
    OWSDisplayedMessageCollectionViewCell *errorCell = [self loadDisplayedMessageCollectionViewCellForIndexPath:indexPath];
    errorCell.textView.text = [errorMessage text];

    // Disable text selectability. Specifying this in prepareForReuse/awakeFromNib was not sufficient.
    errorCell.textView.userInteractionEnabled = NO;
    errorCell.textView.selectable = NO;

    errorCell.messageBubbleContainerView.layer.borderColor = [[UIColor ows_errorMessageBorderColor] CGColor];
    errorCell.headerImageView.image = [UIImage imageNamed:@"error_white"];

    return errorCell;
}

#pragma mark - Adjusting cell label heights


/**
 Due to the usage of JSQMessagesViewController, and it non-conformity to Dynamyc Type
 we're left to our own devices to make this as usable as possible.
 JSQMessagesVC also does not expose the constraint for the input toolbar height nor does it seem to
 give us a method to tell it to re-adjust (I think it should observe the preferredDefaultHeight property).
 
 With that in mind, we use magical runtime to get that property, and if it doesn't exist, we just don't apply the dynamic
 type change. If it does exist, than we apply the font changes and adjust the views to contain them properly.
 
 This is not the prettiest code, but it's working code. We should tag this code for deletion as soon as JSQMessagesVC adops Dynamic type.
 */
- (void)reloadInputToolbarSizeIfNeeded {
    NSLayoutConstraint *heightConstraint = ((NSLayoutConstraint *)[self valueForKeyPath:@"toolbarHeightConstraint"]);
    if (heightConstraint == nil) {
        return;
    }

    [self.inputToolbar.contentView.textView setFont:[UIFont ows_dynamicTypeBodyFont]];

    CGRect f = self.inputToolbar.contentView.textView.frame;
    f.size.height = [self.inputToolbar.contentView.textView sizeThatFits:self.inputToolbar.contentView.textView.frame.size].height;
    self.inputToolbar.contentView.textView.frame = f;

    self.inputToolbar.preferredDefaultHeight = self.inputToolbar.contentView.textView.frame.size.height + 16;
    heightConstraint.constant = self.inputToolbar.preferredDefaultHeight;
    [self.inputToolbar setNeedsLayout];
}


/**
 Called whenever the user manually changes the dynamic type options inside Settings.

 @param notification NSNotification with the dynamic type change information.
 */
- (void)didChangePreferredContentSize:(NSNotification *)notification {
    [self.collectionView.collectionViewLayout setMessageBubbleFont:[UIFont ows_dynamicTypeBodyFont]];
    [self.collectionView reloadData];
    [self reloadInputToolbarSizeIfNeeded];
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                              layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout
    heightForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath {
    if ([self showDateAtIndexPath:indexPath]) {
        return kJSQMessagesCollectionViewCellLabelHeightDefault;
    }

    return 0.0f;
}

- (BOOL)showDateAtIndexPath:(NSIndexPath *)indexPath {
    BOOL showDate = NO;
    if (indexPath.row == 0) {
        showDate = YES;
    } else {
        id<OWSMessageData> currentMessage = [self messageAtIndexPath:indexPath];

        id<OWSMessageData> previousMessage =
            [self messageAtIndexPath:[NSIndexPath indexPathForItem:indexPath.row - 1 inSection:indexPath.section]];

        NSTimeInterval timeDifference = [currentMessage.date timeIntervalSinceDate:previousMessage.date];
        if (timeDifference > kTSMessageSentDateShowTimeInterval) {
            showDate = YES;
        }
    }
    return showDate;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView
    attributedTextForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath {
    if ([self showDateAtIndexPath:indexPath]) {
        id<OWSMessageData> currentMessage = [self messageAtIndexPath:indexPath];

        return [[JSQMessagesTimestampFormatter sharedFormatter] attributedTimestampForDate:currentMessage.date];
    }

    return nil;
}

- (BOOL)shouldShowMessageStatusAtIndexPath:(NSIndexPath *)indexPath
{
    id<OWSMessageData> currentMessage = [self messageAtIndexPath:indexPath];

    if (currentMessage.isExpiringMessage) {
        return YES;
    }

    return !![self collectionView:self.collectionView attributedTextForCellBottomLabelAtIndexPath:indexPath];
}

- (TSOutgoingMessage *)nextOutgoingMessage:(NSIndexPath *)indexPath
{
    NSInteger rowCount = [self.collectionView numberOfItemsInSection:indexPath.section];
    for (NSInteger row = indexPath.row + 1; row < rowCount; row++) {
        id<OWSMessageData> nextMessage = [self messageAtIndexPath:[NSIndexPath indexPathForRow:row
                                                                                     inSection:indexPath.section]];
        if ([nextMessage isKindOfClass:[TSOutgoingMessage class]]) {
            return (TSOutgoingMessage *)nextMessage;
        }
    }
    return nil;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView
    attributedTextForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    id<OWSMessageData> messageData = [self messageAtIndexPath:indexPath];
    if (![messageData isKindOfClass:[TSMessageAdapter class]]) {
        return nil;
    }

    TSMessageAdapter *message = (TSMessageAdapter *)messageData;
    if (message.messageType == TSOutgoingMessageAdapter) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)message.interaction;
        if (outgoingMessage.messageState == TSOutgoingMessageStateUnsent) {
            return [[NSAttributedString alloc] initWithString:NSLocalizedString(@"MESSAGE_STATUS_FAILED",
                                                                                @"message footer for failed messages")];
        } else if (outgoingMessage.messageState == TSOutgoingMessageStateSentToService) {
            NSString *text = (outgoingMessage.wasDelivered
                    ? NSLocalizedString(@"MESSAGE_STATUS_DELIVERED", @"message footer for delivered messages")
                    : NSLocalizedString(@"MESSAGE_STATUS_SENT", @"message footer for sent messages"));
            NSAttributedString *result = [[NSAttributedString alloc] initWithString:text];

            // Show when it's the last message in the thread
            if (indexPath.item == [self.collectionView numberOfItemsInSection:indexPath.section] - 1) {
                [self updateLastDeliveredMessage:message];
                return result;
            }

            // Or when the next message is *not* an outgoing sent/delivered message.
            TSOutgoingMessage *nextMessage = [self nextOutgoingMessage:indexPath];
            if (nextMessage && nextMessage.messageState != TSOutgoingMessageStateSentToService) {
                [self updateLastDeliveredMessage:message];
                return result;
            }
        } else if (message.isMediaBeingSent) {
            return [[NSAttributedString alloc] initWithString:NSLocalizedString(@"MESSAGE_STATUS_UPLOADING",
                                                                                @"message footer while attachment is uploading")];
        } else {
            OWSAssert(outgoingMessage.messageState == TSOutgoingMessageStateAttemptingOut);
            // Show an "..." ellisis icon.
            //
            // TODO: It'd be nice to animate this, but JSQMessageViewController doesn't give us a great way to do so.
            //       We already have problems with unstable cell layout; we don't want to exacerbate them.
            NSAttributedString *result =
            [[NSAttributedString alloc] initWithString:@"/"
                                            attributes:@{
                                                         NSFontAttributeName: [UIFont ows_dripIconsFont:14.f],
                                                         }];
            return result;
        }
    } else if (message.messageType == TSIncomingMessageAdapter && [self.thread isKindOfClass:[TSGroupThread class]]) {
        TSIncomingMessage *incomingMessage = (TSIncomingMessage *)message.interaction;
        NSString *_Nonnull name = [self.contactsManager displayNameForPhoneIdentifier:incomingMessage.authorId];
        NSAttributedString *senderNameString = [[NSAttributedString alloc] initWithString:name];

        return senderNameString;
    }

    return nil;
}

- (void)updateLastDeliveredMessage:(TSMessageAdapter *)newLastDeliveredMessage
{
    if (newLastDeliveredMessage.interaction.timestamp > self.lastDeliveredMessage.interaction.timestamp) {
        TSMessageAdapter *penultimateDeliveredMessage = self.lastDeliveredMessage;
        self.lastDeliveredMessage = newLastDeliveredMessage;
        [penultimateDeliveredMessage.interaction touch];
    }
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                                 layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout
    heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self shouldShowMessageStatusAtIndexPath:indexPath]) {
        return 16.0f;
    }

    return 0.0f;
}

#pragma mark - Actions

- (void)showConversationSettings
{
    if (self.userLeftGroup) {
        DDLogDebug(@"%@ Ignoring request to show conversation settings, since user left group", self.tag);
        return;
    }

    OWSConversationSettingsTableViewController *settingsVC =
        [[UIStoryboard main] instantiateViewControllerWithIdentifier:@"OWSConversationSettingsTableViewController"];
    settingsVC.conversationSettingsViewDelegate = self;
    [settingsVC configureWithThread:self.thread];
    [self.navigationController pushViewController:settingsVC animated:YES];
}

- (void)didTapTimerInNavbar:(id)sender
{
    DDLogDebug(@"%@ Tapped timer in navbar", self.tag);
    [self showConversationSettings];
}


- (void)collectionView:(JSQMessagesCollectionView *)collectionView
    didTapMessageBubbleAtIndexPath:(NSIndexPath *)indexPath
{
    id<OWSMessageData> messageItem = [self messageAtIndexPath:indexPath];
    TSInteraction *interaction = [self interactionAtIndexPath:indexPath];
    
    switch (messageItem.messageType) {
        case TSOutgoingMessageAdapter: {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)interaction;
            if (outgoingMessage.messageState == TSOutgoingMessageStateUnsent) {
                [self handleUnsentMessageTap:outgoingMessage];

                // This `break` is intentionally within the if.
                // We want to activate fullscreen media view for sent items
                // but not those which failed-to-send
                break;
            }
            // No `break` as we want to fall through to capture tapping on Outgoing media items too
        }
        case TSIncomingMessageAdapter: {
            BOOL isMediaMessage = [messageItem isMediaMessage];

            if (isMediaMessage) {
                if ([[messageItem media] isKindOfClass:[TSPhotoAdapter class]]) {
                    TSPhotoAdapter *messageMedia = (TSPhotoAdapter *)[messageItem media];

                    tappedImage = ((UIImageView *)[messageMedia mediaView]).image;
                    if(tappedImage == nil) {
                        DDLogWarn(@"tapped TSPhotoAdapter with nil image");
                    } else {
                        UIWindow *window = [UIApplication sharedApplication].keyWindow;
                        JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *) [collectionView cellForItemAtIndexPath:indexPath];
                        OWSAssert([cell isKindOfClass:[JSQMessagesCollectionViewCell class]]);
                        CGRect convertedRect = [cell.mediaView convertRect:cell.mediaView.bounds
                                                                    toView:window];
                        
                        __block TSAttachment *attachment = nil;
                        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                            attachment =
                            [TSAttachment fetchObjectWithUniqueID:messageMedia.attachmentId transaction:transaction];
                        }];

                        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                            TSAttachmentStream *attStream = (TSAttachmentStream *)attachment;
                            FullImageViewController *vc   = [[FullImageViewController alloc]
                                                             initWithAttachment:attStream
                                                             fromRect:convertedRect
                                                             forInteraction:interaction
                                                             messageItem:messageItem
                                                             isAnimated:NO];

                            [vc presentFromViewController:self];
                        }
                    }
                } else if ([[messageItem media] isKindOfClass:[TSAnimatedAdapter class]]) {
                    // Show animated image full-screen
                    TSAnimatedAdapter *messageMedia = (TSAnimatedAdapter *)[messageItem media];
                    tappedImage                     = ((UIImageView *)[messageMedia mediaView]).image;
                    if(tappedImage == nil) {
                        DDLogWarn(@"tapped TSAnimatedAdapter with nil image");
                    } else {
                        UIWindow *window = [UIApplication sharedApplication].keyWindow;
                        JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *) [collectionView cellForItemAtIndexPath:indexPath];
                        OWSAssert([cell isKindOfClass:[JSQMessagesCollectionViewCell class]]);
                        CGRect convertedRect = [cell.mediaView convertRect:cell.mediaView.bounds
                                                                    toView:window];

                        __block TSAttachment *attachment = nil;
                        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                            attachment =
                            [TSAttachment fetchObjectWithUniqueID:messageMedia.attachmentId transaction:transaction];
                        }];
                        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                            TSAttachmentStream *attStream = (TSAttachmentStream *)attachment;
                            FullImageViewController *vc =
                            [[FullImageViewController alloc] initWithAttachment:attStream
                                                                       fromRect:convertedRect
                                                                 forInteraction:interaction
                                                                    messageItem:messageItem
                                                                     isAnimated:YES];
                            [vc presentFromViewController:self];
                        }
                    }
                } else if ([[messageItem media] isKindOfClass:[TSVideoAttachmentAdapter class]]) {
                    // fileurl disappeared should look up in db as before. will do refactor
                    // full screen, check this setup with a .mov
                    TSVideoAttachmentAdapter *messageMedia = (TSVideoAttachmentAdapter *)[messageItem media];
                    __block TSAttachment *attachment       = nil;
                    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                      attachment =
                          [TSAttachment fetchObjectWithUniqueID:messageMedia.attachmentId transaction:transaction];
                    }];

                    if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                        TSAttachmentStream *attStream = (TSAttachmentStream *)attachment;
                        NSFileManager *fileManager    = [NSFileManager defaultManager];
                        if ([messageMedia isVideo]) {
                            if ([fileManager fileExistsAtPath:[attStream.mediaURL path]]) {
                                [self dismissKeyBoard];
                                self.videoPlayer =
                                    [[MPMoviePlayerController alloc] initWithContentURL:attStream.mediaURL];
                                [_videoPlayer prepareToPlay];

                                [[NSNotificationCenter defaultCenter] addObserver:self
                                                                         selector:@selector(moviePlayerWillExitFullscreen:)
                                                                             name:MPMoviePlayerWillExitFullscreenNotification
                                                                           object:_videoPlayer];
                                [[NSNotificationCenter defaultCenter] addObserver:self
                                                                         selector:@selector(moviePlayerDidExitFullscreen:)
                                                                             name:MPMoviePlayerDidExitFullscreenNotification
                                                                           object:_videoPlayer];

                                _videoPlayer.controlStyle = MPMovieControlStyleDefault;
                                _videoPlayer.shouldAutoplay = YES;
                                [self.view addSubview:_videoPlayer.view];
                                // We can't animate from the cell media frame;
                                // MPMoviePlayerController will animate a crop of its
                                // contents rather than scaling them.
                                _videoPlayer.view.frame = self.view.bounds;
                                [_videoPlayer setFullscreen:YES animated:NO];
                            }
                        } else if ([messageMedia isAudio]) {
                            if (self.audioAttachmentPlayer) {
                                // Is this player associated with this media adapter?
                                if (self.audioAttachmentPlayer.owner == messageMedia) {
                                    // Tap to pause & unpause.
                                    [self.audioAttachmentPlayer togglePlayState];
                                    return;
                                }
                                [self.audioAttachmentPlayer stop];
                                self.audioAttachmentPlayer = nil;
                            }
                            self.audioAttachmentPlayer =
                                [[OWSAudioAttachmentPlayer alloc] initWithMediaAdapter:messageMedia
                                                                    databaseConnection:self.uiDatabaseConnection];
                            // Associate the player with this media adapter.
                            self.audioAttachmentPlayer.owner = messageMedia;
                            [self.audioAttachmentPlayer play];
                        }
                    }
                } else if ([messageItem.media isKindOfClass:[AttachmentPointerAdapter class]]) {
                    AttachmentPointerAdapter *attachmentPointerAdadpter = (AttachmentPointerAdapter *)messageItem.media;
                    TSAttachmentPointer *attachmentPointer = attachmentPointerAdadpter.attachmentPointer;
                    // Restart failed downloads
                    if (attachmentPointer.state == TSAttachmentPointerStateFailed) {
                        if (![interaction isKindOfClass:[TSMessage class]]) {
                            DDLogError(@"%@ Expected attachment downloads from an instance of message, but found: %@", self.tag, interaction);
                            OWSAssert(NO);
                            return;
                        }
                        TSMessage *message = (TSMessage *)interaction;
                        [self handleFailedDownloadTapForMessage:message attachmentPointer:attachmentPointer];
                    } else {
                        DDLogVerbose(@"%@ Ignoring tap for attachment pointer %@ with state %lu",
                            self.tag,
                            attachmentPointer,
                            (unsigned long)attachmentPointer.state);
                    }
                } else {
                    DDLogDebug(@"%@ Unhandled tap on 'media item' with media: %@", self.tag, messageItem.media);
                }
            }
        } break;
        case TSErrorMessageAdapter:
            [self handleErrorMessageTap:(TSErrorMessage *)interaction];
            break;
        case TSCallAdapter:
            break;
        default:
            DDLogDebug(@"Unhandled bubble touch for interaction: %@.", interaction);
            break;
    }

    if (messageItem.messageType == TSOutgoingMessageAdapter ||
        messageItem.messageType == TSIncomingMessageAdapter) {
        TSMessage *message  = (TSMessage *)interaction;
        if ([message hasAttachments]) {
            NSString *attachmentID = message.attachmentIds[0];
            TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentID];
            if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                TSAttachmentStream *stream = (TSAttachmentStream *)attachment;
                // Tapping on incoming and outgoing unknown extensions should show the
                // sharing UI.
                if ([[messageItem media] isKindOfClass:[TSGenericAttachmentAdapter class]]) {
                    [AttachmentSharing showShareUIForAttachment:stream];
                }
                // Tapping on incoming and outgoing "oversize text messages" should show the
                // "oversize text message" view.
                if ([attachment.contentType isEqualToString:OWSMimeTypeOversizeTextMessage]) {
                    OversizeTextMessageViewController *messageVC = [[OversizeTextMessageViewController alloc] initWithMessage:message];
                    [self.navigationController pushViewController:messageVC animated:YES];
                }
            }
        }
    }
}

// There's more than one way to exit the fullscreen video playback.
// There's a done button, a "toggle fullscreen" button and I think
// there's some gestures too.  These fire slightly different notifications.
// We want to hide & clean up the video player immediately in all of
// these cases.
- (void)moviePlayerWillExitFullscreen:(id)sender {
    DDLogDebug(@"%@ %s", self.tag, __PRETTY_FUNCTION__);

    [self clearVideoPlayer];
}

// See comment on moviePlayerWillExitFullscreen:
- (void)moviePlayerDidExitFullscreen:(id)sender {
    DDLogDebug(@"%@ %s", self.tag, __PRETTY_FUNCTION__);
    
    [self clearVideoPlayer];
}

- (void)clearVideoPlayer {
    [_videoPlayer stop];
    [_videoPlayer.view removeFromSuperview];
    self.videoPlayer = nil;
}

- (void)setVideoPlayer:(MPMoviePlayerController *)videoPlayer
{
    _videoPlayer = videoPlayer;

    [ViewControllerUtils setAudioIgnoresHardwareMuteSwitch:videoPlayer != nil];
}

- (void)collectionView:(JSQMessagesCollectionView *)collectionView
                             header:(JSQMessagesLoadEarlierHeaderView *)headerView
    didTapLoadEarlierMessagesButton:(UIButton *)sender {
    if ([self shouldShowLoadEarlierMessages]) {
        self.page++;
    }

    NSInteger item = (NSInteger)[self scrollToItem];

    [self updateRangeOptionsForPage:self.page];

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      [self.messageMappings updateWithTransaction:transaction];
    }];

    [self updateLayoutForEarlierMessagesWithOffset:item];
}

- (BOOL)shouldShowLoadEarlierMessages {
    __block BOOL show = YES;

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      show = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId] <
             [[transaction ext:TSMessageDatabaseViewExtensionName] numberOfItemsInGroup:self.thread.uniqueId];
    }];

    return show;
}

- (NSUInteger)scrollToItem {
    __block NSUInteger item =
        kYapDatabaseRangeLength * (self.page + 1) - [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {

      NSUInteger numberOfVisibleMessages = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];
      NSUInteger numberOfTotalMessages =
          [[transaction ext:TSMessageDatabaseViewExtensionName] numberOfItemsInGroup:self.thread.uniqueId];
      NSUInteger numberOfMessagesToLoad = numberOfTotalMessages - numberOfVisibleMessages;

      BOOL canLoadFullRange = numberOfMessagesToLoad >= kYapDatabaseRangeLength;

      if (!canLoadFullRange) {
          item = numberOfMessagesToLoad;
      }
    }];

    return item == 0 ? item : item - 1;
}

- (void)updateLoadEarlierVisible {
    [self setShowLoadEarlierMessagesHeader:[self shouldShowLoadEarlierMessages]];
}

- (void)updateLayoutForEarlierMessagesWithOffset:(NSInteger)offset {
    [self.collectionView.collectionViewLayout
        invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
    [self.collectionView reloadData];

    [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:offset inSection:0]
                                atScrollPosition:UICollectionViewScrollPositionTop
                                        animated:NO];

    [self updateLoadEarlierVisible];
}

- (void)updateRangeOptionsForPage:(NSUInteger)page {
    YapDatabaseViewRangeOptions *rangeOptions =
        [YapDatabaseViewRangeOptions flexibleRangeWithLength:kYapDatabaseRangeLength * (page + 1)
                                                      offset:0
                                                        from:YapDatabaseViewEnd];

    rangeOptions.maxLength = kYapDatabaseRangeMaxLength;
    rangeOptions.minLength = kYapDatabaseRangeMinLength;

    [self.messageMappings setRangeOptions:rangeOptions forGroup:self.thread.uniqueId];
}

#pragma mark Bubble User Actions

- (void)handleFailedDownloadTapForMessage:(TSMessage *)message
                        attachmentPointer:(TSAttachmentPointer *)attachmentPointer
{
    UIAlertController *actionSheetController = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"MESSAGES_VIEW_FAILED_DOWNLOAD_ACTIONSHEET_TITLE", comment
                                                   : "Action sheet title after tapping on failed download.")
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

    UIAlertAction *deleteMessageAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_DELETE_TITLE", @"")
                                                                  style:UIAlertActionStyleDestructive
                                                                handler:^(UIAlertAction *_Nonnull action) {
                                                                    [message remove];
                                                                }];
    [actionSheetController addAction:deleteMessageAction];

    UIAlertAction *resendMessageAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"MESSAGES_VIEW_FAILED_DOWNLOAD_RETRY_ACTION", @"Action sheet button text")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    OWSAttachmentsProcessor *processor =
                        [[OWSAttachmentsProcessor alloc] initWithAttachmentPointer:attachmentPointer
                                                                    networkManager:self.networkManager];
                    [processor fetchAttachmentsForMessage:message
                        success:^(TSAttachmentStream *_Nonnull attachmentStream) {
                            DDLogInfo(
                                @"%@ Successfully redownloaded attachment in thread: %@", self.tag, message.thread);
                        }
                        failure:^(NSError *_Nonnull error) {
                            DDLogWarn(@"%@ Failed to redownload message with error: %@", self.tag, error);
                        }];
                }];

    [actionSheetController addAction:resendMessageAction];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}


- (void)handleUnsentMessageTap:(TSOutgoingMessage *)message {
    UIAlertController *actionSheetController = [UIAlertController alertControllerWithTitle:message.mostRecentFailureText
                                                                                   message:nil
                                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

    UIAlertAction *deleteMessageAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_DELETE_TITLE", @"")
                                                                  style:UIAlertActionStyleDestructive
                                                                handler:^(UIAlertAction *_Nonnull action) {
                                                                    [message remove];
                                                                }];
    [actionSheetController addAction:deleteMessageAction];

    UIAlertAction *resendMessageAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"SEND_AGAIN_BUTTON", @"")
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^(UIAlertAction * _Nonnull action) {
                                                                    [self.messageSender sendMessage:message
                                                                        success:^{
                                                                            DDLogInfo(@"%@ Successfully resent failed message.", self.tag);
                                                                        }
                                                                        failure:^(NSError *_Nonnull error) {
                                                                            DDLogWarn(@"%@ Failed to send message with error: %@", self.tag, error);
                                                                        }];
                                                                }];

    [actionSheetController addAction:resendMessageAction];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)handleErrorMessageTap:(TSErrorMessage *)message
{
    if ([message isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]) {
        [self tappedInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)message];
    } else if ([message isKindOfClass:[OWSUnknownContactBlockOfferMessage class]]) {
        [self tappedUnknownContactBlockOfferMessage:(OWSUnknownContactBlockOfferMessage *)message];
    } else if (message.errorType == TSErrorMessageInvalidMessage) {
        [self tappedCorruptedMessage:message];
    } else {
        DDLogWarn(@"%@ Unhandled tap for error message:%@", self.tag, message);
    }
}

- (void)tappedCorruptedMessage:(TSErrorMessage *)message
{

    NSString *alertMessage = [NSString
        stringWithFormat:NSLocalizedString(@"CORRUPTED_SESSION_DESCRIPTION", @"ActionSheet title"), self.thread.name];

    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil
                                                                             message:alertMessage
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [alertController addAction:dismissAction];
    
    UIAlertAction *resetSessionAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"FINGERPRINT_SHRED_KEYMATERIAL_BUTTON", @"")
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^(UIAlertAction * _Nonnull action) {
                                                                    if (![self.thread isKindOfClass:[TSContactThread class]]) {
                                                                        // Corrupt Message errors only appear in contact threads.
                                                                        DDLogError(@"%@ Unexpected request to reset session in group thread. Refusing", self.tag);
                                                                            return;
                                                                    }
                                                                    TSContactThread *contactThread = (TSContactThread *)self.thread;
                                                                    [OWSSessionResetJob
                                                                        runWithContactThread:contactThread
                                                                               messageSender:self.messageSender
                                                                              storageManager:self.storageManager];
                                                               }];
    [alertController addAction:resetSessionAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)tappedInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)errorMessage
{
    NSString *keyOwner = [self.contactsManager displayNameForPhoneIdentifier:errorMessage.theirSignalId];
    NSString *titleFormat = NSLocalizedString(@"SAFETY_NUMBERS_ACTIONSHEET_TITLE", @"Action sheet heading");
    NSString *titleText = [NSString stringWithFormat:titleFormat, keyOwner];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:titleText
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

    UIAlertAction *showSafteyNumberAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"SHOW_SAFETY_NUMBER_ACTION", @"Action sheet item")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *_Nonnull action) {
                                   DDLogInfo(@"%@ Remote Key Changed actions: Show fingerprint display", self.tag);
                                   [self showFingerprintWithTheirIdentityKey:errorMessage.newIdentityKey
                                                               theirSignalId:errorMessage.theirSignalId];
                               }];
    [actionSheetController addAction:showSafteyNumberAction];

    UIAlertAction *acceptSafetyNumberAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"ACCEPT_NEW_IDENTITY_ACTION", @"Action sheet item")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    DDLogInfo(@"%@ Remote Key Changed actions: Accepted new identity key", self.tag);
                    [errorMessage acceptNewIdentityKey];
                    if ([errorMessage isKindOfClass:[TSInvalidIdentityKeySendingErrorMessage class]]) {
                        [self.messageSender
                            resendMessageFromKeyError:(TSInvalidIdentityKeySendingErrorMessage *)errorMessage
                            success:^{
                                DDLogDebug(@"%@ Successfully resent key-error message.", self.tag);
                            }
                            failure:^(NSError *_Nonnull error) {
                                DDLogError(@"%@ Failed to resend key-error message with error:%@", self.tag, error);
                            }];
                    }
                }];
    [actionSheetController addAction:acceptSafetyNumberAction];
    
    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)tappedUnknownContactBlockOfferMessage:(OWSUnknownContactBlockOfferMessage *)errorMessage
{
    NSString *displayName = [self.contactsManager displayNameForPhoneIdentifier:errorMessage.contactId];
    NSString *title =
        [NSString stringWithFormat:NSLocalizedString(@"BLOCK_OFFER_ACTIONSHEET_TITLE_FORMAT",
                                       @"Title format for action sheet that offers to block an unknown user."
                                       @"Embeds {{the unknown user's name or phone number}}."),
                  [BlockListUIUtils formatDisplayNameForAlertTitle:displayName]];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

    UIAlertAction *blockAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_OFFER_ACTIONSHEET_BLOCK_ACTION",
                                           @"Action sheet that will block an unknown user.")
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *_Nonnull action) {
                                   DDLogInfo(@"%@ Blocking an unknown user.", self.tag);
                                   [self.blockingManager addBlockedPhoneNumber:errorMessage.contactId];
                                   // Delete the block offer.
                                   [self.storageManager.dbConnection
                                       readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                           [errorMessage removeWithTransaction:transaction];
                                       }];
                               }];
    [actionSheetController addAction:blockAction];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}


#pragma mark - Attachment Picking: Documents

- (void)showAttachmentDocumentPicker
{
    NSString *allItems = (__bridge NSString *)kUTTypeItem;
    NSArray<NSString *> *documentTypes = @[ allItems ];
    // UIDocumentPickerModeImport copies to a temp file within our container.
    // It uses more memory than "open" but lets us avoid working with security scoped URLs.
    UIDocumentPickerMode pickerMode = UIDocumentPickerModeImport;
    UIDocumentMenuViewController *menuController =
        [[UIDocumentMenuViewController alloc] initWithDocumentTypes:documentTypes inMode:pickerMode];
    menuController.delegate = self;
    [self presentViewController:menuController animated:YES completion:nil];
}

#pragma mark UIDocumentMenuDelegate

- (void)documentMenu:(UIDocumentMenuViewController *)documentMenu
    didPickDocumentPicker:(UIDocumentPickerViewController *)documentPicker
{
    documentPicker.delegate = self;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

#pragma mark UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url
{
    DDLogDebug(@"%@ Picked document at url: %@", self.tag, url);
    NSData *attachmentData = [NSData dataWithContentsOfURL:url];

    NSString *type;
    NSError *typeError;
    [url getResourceValue:&type forKey:NSURLTypeIdentifierKey error:&typeError];
    if (typeError) {
        DDLogError(
            @"%@ Determining type of picked document at url: %@ failed with error: %@", self.tag, url, typeError);
        OWSAssert(NO);
    }
    if (!type) {
        DDLogDebug(@"%@ falling back to default filetype for picked document at url: %@", self.tag, url);
        OWSAssert(NO);
        type = (__bridge NSString *)kUTTypeData;
    }

    NSNumber *isDirectory;
    NSError *isDirectoryError;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&isDirectoryError];
    if (isDirectoryError) {
        DDLogError(@"%@ Determining if picked document at url: %@ was a directory failed with error: %@",
            self.tag,
            url,
            isDirectoryError);
        OWSAssert(NO);
    } else if ([isDirectory boolValue]) {
        DDLogInfo(@"%@ User picked directory at url: %@", self.tag, url);
        UIAlertController *alertController = [UIAlertController
            alertControllerWithTitle:
                NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_TITLE",
                    @"Alert title when picking a document fails because user picked a directory/bundle")
                             message:
                                 NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_BODY",
                                     @"Alert body when picking a document fails because user picked a directory/bundle")
                      preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"DISMISS_BUTTON_TEXT", nil)
                                                                style:UIAlertActionStyleCancel
                                                              handler:nil];
        [alertController addAction:dismissAction];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:alertController animated:YES completion:nil];
        });
        return;
    }

    NSString *filename = url.lastPathComponent;
    if (!filename) {
        DDLogDebug(@"%@ Unable to determine filename from url: %@", self.tag, url);
        OWSAssert(NO);
        filename = NSLocalizedString(
            @"ATTACHMENT_DEFAULT_FILENAME", @"Generic filename for an attachment with no known name");
    }

    if (!attachmentData || attachmentData.length == 0) {
        DDLogError(@"%@ attachment data was unexpectedly empty for picked document url: %@", self.tag, url);
        OWSAssert(NO);
        UIAlertController *alertController = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_FAILED_ALERT_TITLE",
                                         @"Alert title when picking a document fails for an unknown reason")
                             message:nil
                      preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"DISMISS_BUTTON_TEXT", nil)
                                                                style:UIAlertActionStyleCancel
                                                              handler:nil];
        [alertController addAction:dismissAction];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:alertController animated:YES completion:nil];
        });
        return;
    }

    OWSAssert(attachmentData);
    OWSAssert(type);
    OWSAssert(filename);
    SignalAttachment *attachment = [SignalAttachment attachmentWithData:attachmentData dataUTI:type filename:filename];
    [self tryToSendAttachmentIfApproved:attachment];
}

#pragma mark - UIImagePickerController

/*
 *  Presenting UIImagePickerController
 */

- (void)takePictureOrVideo {
    [self ows_askForCameraPermissions:^{
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage, (__bridge NSString *)kUTTypeMovie ];
        picker.allowsEditing = NO;
        picker.delegate = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
        });
    }
                   alertActionHandler:nil];
}
- (void)chooseFromLibrary {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        DDLogError(@"PhotoLibrary ImagePicker source not available");
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage, (__bridge NSString *)kUTTypeMovie ];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
    });
}

/*
 *  Dismissing UIImagePickerController
 */

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [UIUtil modalCompletionBlock]();
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetFrame {
    // fixes bug on frame being off after this selection
    CGRect frame    = [UIScreen mainScreen].applicationFrame;
    self.view.frame = frame;
}

/*
 *  Fetching data from UIImagePickerController
 */
- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary<NSString *, id> *)info
{
    [UIUtil modalCompletionBlock]();
    [self resetFrame];

    NSURL *referenceURL = [info valueForKey:UIImagePickerControllerReferenceURL];
    if (!referenceURL) {
        DDLogVerbose(@"Could not retrieve reference URL for picked asset");
        [self imagePickerController:picker didFinishPickingMediaWithInfo:info filename:nil];
        return;
    }

    ALAssetsLibraryAssetForURLResultBlock resultblock = ^(ALAsset *imageAsset) {
        ALAssetRepresentation *imageRep = [imageAsset defaultRepresentation];
        NSString *filename = [imageRep filename];
        [self imagePickerController:picker didFinishPickingMediaWithInfo:info filename:filename];
    };

    ALAssetsLibrary *assetslibrary = [[ALAssetsLibrary alloc] init];
    [assetslibrary assetForURL:referenceURL
                   resultBlock:resultblock
                  failureBlock:^(NSError *error) {
                      DDLogError(@"Error retrieving filename for asset: %@", error);
                      OWSAssert(0);
                  }];
}

- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary<NSString *, id> *)info
                         filename:(NSString *)filename
{
    OWSAssert([NSThread isMainThread]);

    void (^failedToPickAttachment)(NSError *error) = ^void(NSError *error) {
        DDLogError(@"failed to pick attachment with error: %@", error);
    };

    NSString *mediaType = info[UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:(__bridge NSString *)kUTTypeMovie]) {
        // Video picked from library or captured with camera

        BOOL isFromCamera = picker.sourceType == UIImagePickerControllerSourceTypeCamera;
        NSURL *videoURL = info[UIImagePickerControllerMediaURL];
        [self dismissViewControllerAnimated:YES
                                 completion:^{
                                     [self sendQualityAdjustedAttachmentForVideo:videoURL
                                                                        filename:filename
                                                              skipApprovalDialog:isFromCamera];
                                 }];
    } else if (picker.sourceType == UIImagePickerControllerSourceTypeCamera) {
        // Static Image captured from camera

        UIImage *imageFromCamera = [info[UIImagePickerControllerOriginalImage] normalizedImage];

        [self dismissViewControllerAnimated:YES
                                 completion:^{
                                     OWSAssert([NSThread isMainThread]);
                                     
                                     if (imageFromCamera) {
                                         SignalAttachment *attachment =
                                             [SignalAttachment imageAttachmentWithImage:imageFromCamera
                                                                                dataUTI:(NSString *)kUTTypeJPEG
                                                                               filename:filename];
                                         if (!attachment ||
                                             [attachment hasError]) {
                                             DDLogWarn(@"%@ %s Invalid attachment: %@.",
                                                       self.tag,
                                                       __PRETTY_FUNCTION__,
                                                       attachment ? [attachment errorName] : @"Missing data");
                                             [self showErrorAlertForAttachment:attachment];
                                             failedToPickAttachment(nil);
                                         } else {
                                             [self tryToSendAttachmentIfApproved:attachment skipApprovalDialog:YES];
                                         }
                                     } else {
                                         failedToPickAttachment(nil);
                                     }
                                 }];
    } else {
        // Non-Video image picked from library

        NSURL *assetURL = info[UIImagePickerControllerReferenceURL];
        PHAsset *asset = [[PHAsset fetchAssetsWithALAssetURLs:@[ assetURL ] options:nil] lastObject];
        if (!asset) {
            return failedToPickAttachment(nil);
        }

        PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
        options.synchronous = YES; // We're only fetching one asset.
        options.networkAccessAllowed = YES; // iCloud OK
        options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat; // Don't need quick/dirty version
        [[PHImageManager defaultManager]
         requestImageDataForAsset:asset
         options:options
         resultHandler:^(NSData *_Nullable imageData,
                         NSString *_Nullable dataUTI,
                         UIImageOrientation orientation,
                         NSDictionary *_Nullable assetInfo) {
             
             NSError *assetFetchingError = assetInfo[PHImageErrorKey];
             if (assetFetchingError || !imageData) {
                 return failedToPickAttachment(assetFetchingError);
             }
             OWSAssert([NSThread isMainThread]);

             SignalAttachment *attachment =
                 [SignalAttachment attachmentWithData:imageData dataUTI:dataUTI filename:filename];
             [self dismissViewControllerAnimated:YES
                                      completion:^{
                                          OWSAssert([NSThread isMainThread]);
                                          if (!attachment ||
                                              [attachment hasError]) {
                                              DDLogWarn(@"%@ %s Invalid attachment: %@.",
                                                        self.tag,
                                                        __PRETTY_FUNCTION__,
                                                        attachment ? [attachment errorName] : @"Missing data");
                                              [self showErrorAlertForAttachment:attachment];
                                              failedToPickAttachment(nil);
                                          } else {
                                              [self tryToSendAttachmentIfApproved:attachment];
                                          }
                                      }];
         }];
    }
}

- (void)sendMessageAttachment:(SignalAttachment *)attachment
{
    OWSAssert([NSThread isMainThread]);
    // TODO: Should we assume non-nil or should we check for non-nil?
    OWSAssert(attachment != nil);
    OWSAssert(![attachment hasError]);
    OWSAssert([attachment mimeType].length > 0);

    DDLogVerbose(@"Sending attachment. Size in bytes: %lu, contentType: %@",
        (unsigned long)attachment.data.length,
        [attachment mimeType]);
    [ThreadUtil sendMessageWithAttachment:attachment inThread:self.thread messageSender:self.messageSender];
}

- (NSURL *)videoTempFolder {
    NSArray *paths     = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    basePath           = [basePath stringByAppendingPathComponent:@"videos"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:basePath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:basePath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    return [NSURL fileURLWithPath:basePath];
}

- (void)sendQualityAdjustedAttachmentForVideo:(NSURL *)movieURL
                                     filename:(NSString *)filename
                           skipApprovalDialog:(BOOL)skipApprovalDialog
{
    AVAsset *video = [AVAsset assetWithURL:movieURL];
    AVAssetExportSession *exportSession =
        [AVAssetExportSession exportSessionWithAsset:video presetName:AVAssetExportPresetMediumQuality];
    exportSession.shouldOptimizeForNetworkUse = YES;
    exportSession.outputFileType              = AVFileTypeMPEG4;

    double currentTime     = [[NSDate date] timeIntervalSince1970];
    NSString *strImageName = [NSString stringWithFormat:@"%f", currentTime];
    NSURL *compressedVideoUrl =
        [[self videoTempFolder] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", strImageName]];

    exportSession.outputURL = compressedVideoUrl;
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        NSData *videoData = [NSData dataWithContentsOfURL:compressedVideoUrl];
        dispatch_async(dispatch_get_main_queue(), ^{
            SignalAttachment *attachment =
                [SignalAttachment attachmentWithData:videoData dataUTI:(NSString *)kUTTypeMPEG4 filename:filename];
            if (!attachment || [attachment hasError]) {
                DDLogWarn(@"%@ %s Invalid attachment: %@.",
                    self.tag,
                    __PRETTY_FUNCTION__,
                    attachment ? [attachment errorName] : @"Missing data");
                [self showErrorAlertForAttachment:attachment];
            } else {
                [self tryToSendAttachmentIfApproved:attachment skipApprovalDialog:skipApprovalDialog];
            }

            NSError *error;
            [[NSFileManager defaultManager] removeItemAtURL:compressedVideoUrl error:&error];
            if (error) {
                DDLogWarn(@"Failed to remove cached video file: %@", error.debugDescription);
            }
        });
    }];
}


#pragma mark Storage access

- (YapDatabaseConnection *)uiDatabaseConnection {
    NSAssert([NSThread isMainThread], @"Must access uiDatabaseConnection on main thread!");
    if (!_uiDatabaseConnection) {
        _uiDatabaseConnection = [self.storageManager newDatabaseConnection];
        [_uiDatabaseConnection beginLongLivedReadTransaction];
    }
    return _uiDatabaseConnection;
}

- (YapDatabaseConnection *)editingDatabaseConnection {
    if (!_editingDatabaseConnection) {
        _editingDatabaseConnection = [self.storageManager newDatabaseConnection];
    }
    return _editingDatabaseConnection;
}

- (void)yapDatabaseModified:(NSNotification *)notification {
    // Currently, we update thread and message state every time
    // the database is modified.  That doesn't seem optimal, but
    // in practice it's efficient enough.

    // We need to `beginLongLivedReadTransaction` before we update our
    // models in order to jump to the most recent commit.
    NSArray *notifications = [self.uiDatabaseConnection beginLongLivedReadTransaction];

    [self updateBackButtonUnreadCount];
    [self updateNavigationBarSubtitleLabel];

    if (isGroupConversation) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
          TSGroupThread *gThread = (TSGroupThread *)self.thread;

          if (gThread.groupModel) {
              self.thread = [TSGroupThread threadWithGroupModel:gThread.groupModel transaction:transaction];
          }
        }];
        [self setNavigationTitle];
    }

    if (![[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName]
            hasChangesForNotifications:notifications]) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
          [self.messageMappings updateWithTransaction:transaction];
        }];
        return;
    }

    // HACK to work around radar #28167779
    // "UICollectionView performBatchUpdates can trigger a crash if the collection view is flagged for layout"
    // more: https://github.com/PSPDFKit-labs/radar.apple.com/tree/master/28167779%20-%20CollectionViewBatchingIssue
    // This was our #2 crash, and much exacerbated by the refactoring somewhere between 2.6.2.0-2.6.3.8
    [self.collectionView layoutIfNeeded];
    // ENDHACK to work around radar #28167779

    NSArray *messageRowChanges = nil;
    NSArray *sectionChanges    = nil;
    [[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName] getSectionChanges:&sectionChanges
                                                                               rowChanges:&messageRowChanges
                                                                         forNotifications:notifications
                                                                             withMappings:self.messageMappings];

    if ([sectionChanges count] == 0 & [messageRowChanges count] == 0) {
        return;
    }
    
    const CGFloat kIsAtBottomTolerancePts = 5;
    BOOL wasAtBottom = (self.collectionView.contentOffset.y +
                        self.collectionView.bounds.size.height +
                        kIsAtBottomTolerancePts >=
                        self.collectionView.contentSize.height);
    // We want sending messages to feel snappy.  So, if the only
    // update is a new outgoing message AND we're already scrolled to
    // the bottom of the conversation, skip the scroll animation.
    __block BOOL shouldAnimateScrollToBottom = !wasAtBottom;
    // We want to scroll to the bottom if the user:
    //
    // a) already was at the bottom of the conversation.
    // b) is inserting new interactions.
    __block BOOL scrollToBottom = wasAtBottom;

    [self.collectionView performBatchUpdates:^{
      for (YapDatabaseViewRowChange *rowChange in messageRowChanges) {
          switch (rowChange.type) {
              case YapDatabaseViewChangeDelete: {
                  [self.collectionView deleteItemsAtIndexPaths:@[ rowChange.indexPath ]];

                  YapCollectionKey *collectionKey = rowChange.collectionKey;
                  if (collectionKey.key) {
                      [self.messageAdapterCache removeObjectForKey:collectionKey.key];
                  }
                  
                  break;
              }
              case YapDatabaseViewChangeInsert: {
                  [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath ]];
                  scrollToBottom = YES;
                  
                  TSInteraction *interaction = [self interactionAtIndexPath:rowChange.newIndexPath];
                  if (![interaction isKindOfClass:[TSOutgoingMessage class]]) {
                      shouldAnimateScrollToBottom = YES;
                  }
                  break;
              }
              case YapDatabaseViewChangeMove: {
                  [self.collectionView deleteItemsAtIndexPaths:@[ rowChange.indexPath ]];
                  [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath ]];
                  break;
              }
              case YapDatabaseViewChangeUpdate: {
                  YapCollectionKey *collectionKey = rowChange.collectionKey;
                  if (collectionKey.key) {
                      [self.messageAdapterCache removeObjectForKey:collectionKey.key];
                  }
                  [self.collectionView reloadItemsAtIndexPaths:@[ rowChange.indexPath ]];
                  break;
              }
          }
      }
    }
        completion:^(BOOL success) {
          if (!success) {
              [self.collectionView.collectionViewLayout
                  invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
              [self.collectionView reloadData];
          }
          if (scrollToBottom) {
              [self scrollToBottomAnimated:shouldAnimateScrollToBottom];
          }
        }];
}

#pragma mark - UICollectionView DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    NSInteger numberOfMessages = (NSInteger)[self.messageMappings numberOfItemsInSection:(NSUInteger)section];
    return numberOfMessages;
}

- (TSInteraction *)interactionAtIndexPath:(NSIndexPath *)indexPath {
    __block TSInteraction *message = nil;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSMessageDatabaseViewExtensionName];
      NSParameterAssert(viewTransaction != nil);
      NSParameterAssert(self.messageMappings != nil);
      NSParameterAssert(indexPath != nil);
      NSUInteger row                    = (NSUInteger)indexPath.row;
      NSUInteger section                = (NSUInteger)indexPath.section;
      NSUInteger numberOfItemsInSection __unused = [self.messageMappings numberOfItemsInSection:section];
      NSAssert(row < numberOfItemsInSection,
               @"Cannot fetch message because row %d is >= numberOfItemsInSection %d",
               (int)row,
               (int)numberOfItemsInSection);

      message = [viewTransaction objectAtRow:row inSection:section withMappings:self.messageMappings];
      NSParameterAssert(message != nil);
    }];

    return message;
}

- (id<OWSMessageData>)messageAtIndexPath:(NSIndexPath *)indexPath
{
    TSInteraction *interaction = [self interactionAtIndexPath:indexPath];

    id<OWSMessageData> messageAdapter = [self.messageAdapterCache objectForKey:interaction.uniqueId];

    if (!messageAdapter) {
        messageAdapter = [TSMessageAdapter messageViewDataWithInteraction:interaction inThread:self.thread contactsManager:self.contactsManager];
        [self.messageAdapterCache setObject:messageAdapter forKey: interaction.uniqueId];
    }

    return messageAdapter;
}

#pragma mark - Audio

- (void)startRecordingVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"startRecordingVoiceMemo");

    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *filename = [NSString stringWithFormat:@"%lld.m4a", [NSDate ows_millisecondTimeStamp]];
    NSString *filepath = [temporaryDirectory stringByAppendingPathComponent:filename];
    NSURL *fileURL = [NSURL fileURLWithPath:filepath];

    // Setup audio session
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error;
    [session setCategory:AVAudioSessionCategoryRecord error:&error];
    if (error) {
        DDLogError(@"%@ Couldn't configure audio session: %@", self.tag, error);
        [self cancelVoiceMemo];
        OWSAssert(0);
        return;
    }

    // Initiate and prepare the recorder
    self.audioRecorder = [[AVAudioRecorder alloc] initWithURL:fileURL
                                                     settings:@{
                                                         AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                                         AVSampleRateKey : @(44100),
                                                         AVNumberOfChannelsKey : @(2),
                                                         AVEncoderBitRateKey: @(128 * 1024),
                                                     }
                                                        error:&error];
    if (error) {
        DDLogError(@"%@ Couldn't create audioRecorder: %@", self.tag, error);
        [self cancelVoiceMemo];
        OWSAssert(0);
        return;
    }

    self.audioRecorder.meteringEnabled = YES;

    if (![self.audioRecorder prepareToRecord]) {
        DDLogError(@"%@ audioRecorder couldn't prepareToRecord.", self.tag);
        [self cancelVoiceMemo];
        OWSAssert(0);
        return;
    }

    if (![self.audioRecorder record]) {
        DDLogError(@"%@ audioRecorder couldn't record.", self.tag);
        [self cancelVoiceMemo];
        OWSAssert(0);
        return;
    }

    if (session.recordPermission != AVAudioSessionRecordPermissionGranted) {
        DDLogInfo(@"%@ we do not have recording permission.", self.tag);
        [self cancelVoiceMemo];
        [OWSAlerts showNoMicrophonePermissionAlert];
        return;
    }
}

- (void)endRecordingVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"endRecordingVoiceMemo");

    if (!self.audioRecorder) {
        DDLogError(@"%@ Missing audioRecorder", self.tag);
        OWSAssert(0);
        return;
    }

    NSTimeInterval currentTime = self.audioRecorder.currentTime;

    [self.audioRecorder stop];

    const NSTimeInterval kMinimumRecordingTimeSeconds = 1.f;
    if (currentTime < kMinimumRecordingTimeSeconds) {
        DDLogInfo(@"Discarding voice message; too short.");
        self.audioRecorder = nil;

        [OWSAlerts
            showAlertWithTitle:
                NSLocalizedString(@"VOICE_MESSAGE_TOO_SHORT_ALERT_TITLE",
                    @"Title for the alert indicating the 'voice message' needs to be held to be held down to record.")
                       message:NSLocalizedString(@"VOICE_MESSAGE_TOO_SHORT_ALERT_MESSAGE",
                                   @"Message for the alert indicating the 'voice message' needs to be held to be held "
                                   @"down to record.")];
        return;
    }

    NSData *audioData = [NSData dataWithContentsOfURL:self.audioRecorder.url];

    if (!audioData) {
        DDLogError(@"%@ Couldn't load audioRecorder data", self.tag);
        OWSAssert(0);
        self.audioRecorder = nil;
        return;
    }

    self.audioRecorder = nil;

    NSString *filename = [NSLocalizedString(@"VOICE_MESSAGE_FILE_NAME", @"Filename for voice messages.")
        stringByAppendingPathExtension:@"m4a"];

    SignalAttachment *attachment = [SignalAttachment voiceMessageAttachmentWithData:audioData
                                                                            dataUTI:(NSString *)kUTTypeMPEG4Audio
                                                                           filename:filename];
    if (!attachment || [attachment hasError]) {
        DDLogWarn(@"%@ %s Invalid attachment: %@.",
            self.tag,
            __PRETTY_FUNCTION__,
            attachment ? [attachment errorName] : @"Missing data");
        [self showErrorAlertForAttachment:attachment];
    } else {
        [self tryToSendAttachmentIfApproved:attachment skipApprovalDialog:YES];
    }
}

- (void)cancelRecordingVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"cancelRecordingVoiceMemo");

    [self resetRecordingVoiceMemo];
}

- (void)resetRecordingVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

    [self.audioRecorder stop];
    self.audioRecorder = nil;
}

#pragma mark Accessory View

- (void)didPressAccessoryButton:(UIButton *)sender {

    if ([self isBlockedContactConversation]) {
        __weak MessagesViewController *weakSelf = self;
        [self showUnblockContactUI:^(BOOL isBlocked) {
            if (!isBlocked) {
                [weakSelf didPressAccessoryButton:nil];
            }
        }];
        return;
    }

    UIAlertController *actionSheetController = [UIAlertController alertControllerWithTitle:nil
                                                                                   message:nil
                                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [actionSheetController addAction:cancelAction];
    
    UIAlertAction *takeMediaAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"MEDIA_FROM_CAMERA_BUTTON", @"media picker option to take photo or video")
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction * _Nonnull action) {
                                                                [self takePictureOrVideo];
                                                            }];
    UIImage *takeMediaImage = [UIImage imageNamed:@"actionsheet_camera_black"];
    OWSAssert(takeMediaImage);
    [takeMediaAction setValue:takeMediaImage forKey:@"image"];
    [actionSheetController addAction:takeMediaAction];

    UIAlertAction *chooseMediaAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"MEDIA_FROM_LIBRARY_BUTTON", @"media picker option to choose from library")
                                          style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction * _Nonnull action) {
                                             [self chooseFromLibrary];
                                         }];
    UIImage *chooseMediaImage = [UIImage imageNamed:@"actionsheet_camera_roll_black"];
    OWSAssert(chooseMediaImage);
    [chooseMediaAction setValue:chooseMediaImage forKey:@"image"];
    [actionSheetController addAction:chooseMediaAction];

    UIAlertAction *chooseDocumentAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"MEDIA_FROM_DOCUMENT_PICKER_BUTTON",
                                           @"action sheet button title when choosing attachment type")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *_Nonnull action) {
                                   [self showAttachmentDocumentPicker];
                               }];
    UIImage *chooseDocumentImage = [UIImage imageNamed:@"actionsheet_document_black"];
    OWSAssert(chooseDocumentImage);
    [chooseDocumentAction setValue:chooseDocumentImage forKey:@"image"];
    [actionSheetController addAction:chooseDocumentAction];

    [self presentViewController:actionSheetController animated:true completion:nil];
}

- (void)markAllMessagesAsRead
{
    [self.thread markAllAsRead];

    // In theory this should be unnecessary as read-status starts expiration
    // but in practice I've seen messages not have their timer started.
    [OWSDisappearingMessagesJob setExpirationsForThread:self.thread];
}

- (BOOL)collectionView:(UICollectionView *)collectionView
      canPerformAction:(SEL)action
    forItemAtIndexPath:(NSIndexPath *)indexPath
            withSender:(id)sender
{
    id<OWSMessageData> messageData = [self messageAtIndexPath:indexPath];
    return [messageData canPerformEditingAction:action];
}

- (void)collectionView:(UICollectionView *)collectionView
         performAction:(SEL)action
    forItemAtIndexPath:(NSIndexPath *)indexPath
            withSender:(id)sender
{
    id<OWSMessageData> messageData = [self messageAtIndexPath:indexPath];
    [messageData performEditingAction:action];
}

- (void)updateGroupModelTo:(TSGroupModel *)newGroupModel
{
    __block TSGroupThread *groupThread;
    __block TSOutgoingMessage *message;

    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        groupThread            = [TSGroupThread getOrCreateThreadWithGroupModel:newGroupModel transaction:transaction];
        
        NSString *updateGroupInfo = [groupThread.groupModel getInfoStringAboutUpdateTo:newGroupModel contactsManager:self.contactsManager];

        groupThread.groupModel = newGroupModel;
        [groupThread saveWithTransaction:transaction];
        message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                      inThread:groupThread
                                              groupMetaMessage:TSGroupMessageUpdate];
        [message updateWithCustomMessage:updateGroupInfo transaction:transaction];
    }];

    if (newGroupModel.groupImage) {
        [self.messageSender sendAttachmentData:UIImagePNGRepresentation(newGroupModel.groupImage)
            contentType:OWSMimeTypeImagePng
            filename:nil
            inMessage:message
            success:^{
                DDLogDebug(@"%@ Successfully sent group update with avatar", self.tag);
            }
            failure:^(NSError *_Nonnull error) {
                DDLogError(@"%@ Failed to send group avatar update with error: %@", self.tag, error);
            }];
    } else {
        [self.messageSender sendMessage:message
            success:^{
                DDLogDebug(@"%@ Successfully sent group update", self.tag);
            }
            failure:^(NSError *_Nonnull error) {
                DDLogError(@"%@ Failed to send group update with error: %@", self.tag, error);
            }];
    }

    self.thread = groupThread;
}

- (void)popKeyBoard {
    [self.inputToolbar.contentView.textView becomeFirstResponder];
}

- (void)dismissKeyBoard {
    [self.inputToolbar.contentView.textView resignFirstResponder];
}

#pragma mark Drafts

- (void)loadDraftInCompose {
    __block NSString *placeholder;
    [self.editingDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
      placeholder = [_thread currentDraftWithTransaction:transaction];
    }
        completionBlock:^{
          dispatch_async(dispatch_get_main_queue(), ^{
            [self.inputToolbar.contentView.textView setText:placeholder];
            [self textViewDidChange:self.inputToolbar.contentView.textView];
          });
        }];
}

- (void)saveDraft {
    if (self.inputToolbar.hidden == NO) {
        __block TSThread *thread       = _thread;
        __block NSString *currentDraft = self.inputToolbar.contentView.textView.text;

        [self.editingDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [thread setDraft:currentDraft transaction:transaction];
        }];
    }
}

- (void)clearDraft
{
    __block TSThread *thread = _thread;
    [self.editingDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [thread setDraft:@"" transaction:transaction];
    }];
}

#pragma mark Unread Badge

- (void)updateBackButtonUnreadCount
{
    AssertIsOnMainThread();
    self.backButtonUnreadCount = [self.messagesManager unreadMessagesCountExcept:self.thread];
}

- (void)setBackButtonUnreadCount:(NSUInteger)unreadCount
{
    AssertIsOnMainThread();
    if (_backButtonUnreadCount == unreadCount) {
        // No need to re-render same count.
        return;
    }
    _backButtonUnreadCount = unreadCount;

    OWSAssert(_backButtonUnreadCountView != nil);
    _backButtonUnreadCountView.hidden = unreadCount <= 0;

    OWSAssert(_backButtonUnreadCountLabel != nil);
    _backButtonUnreadCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)unreadCount];
}

#pragma mark 3D Touch Preview Actions

- (NSArray<id<UIPreviewActionItem>> *)previewActionItems {
    return @[];
}

#pragma mark - Event Handling

- (void)navigationTitleTapped:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateRecognized) {
        [self showConversationSettings];
    }
}

#ifdef DEBUG
- (void)navigationTitleLongPressed:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        [DebugUITableViewController presentDebugUIForThread:self.thread
                                         fromViewController:self];
    }
}
#endif

#pragma mark - JSQMessagesComposerTextViewPasteDelegate

- (BOOL)composerTextView:(JSQMessagesComposerTextView *)textView
   shouldPasteWithSender:(id)sender {
    return YES;
}

#pragma mark - OWSTextViewPasteDelegate

- (void)didPasteAttachment:(SignalAttachment * _Nullable)attachment {
    DDLogError(@"%@ %s",
               self.tag,
               __PRETTY_FUNCTION__);

    [self tryToSendAttachmentIfApproved:attachment];
}

- (void)tryToSendAttachmentIfApproved:(SignalAttachment *_Nullable)attachment
{
    [self tryToSendAttachmentIfApproved:attachment skipApprovalDialog:NO];
}

- (void)tryToSendAttachmentIfApproved:(SignalAttachment *_Nullable)attachment
                   skipApprovalDialog:(BOOL)skipApprovalDialog
{
    DDLogError(@"%@ %s", self.tag, __PRETTY_FUNCTION__);

    DispatchMainThreadSafe(^{
        if ([self isBlockedContactConversation]) {
            __weak MessagesViewController *weakSelf = self;
            [self showUnblockContactUI:^(BOOL isBlocked) {
                if (!isBlocked) {
                    [weakSelf tryToSendAttachmentIfApproved:attachment];
                }
            }];
            return;
        }

        if (attachment == nil || [attachment hasError]) {
            DDLogWarn(@"%@ %s Invalid attachment: %@.",
                self.tag,
                __PRETTY_FUNCTION__,
                attachment ? [attachment errorName] : @"Missing data");
            [self showErrorAlertForAttachment:attachment];
        } else if (skipApprovalDialog) {
            [self sendMessageAttachment:attachment];
        } else {
            __weak MessagesViewController *weakSelf = self;
            UIViewController *viewController =
                [[AttachmentApprovalViewController alloc] initWithAttachment:attachment
                                                           successCompletion:^{
                                                               [weakSelf sendMessageAttachment:attachment];
                                                           }];
            UINavigationController *navigationController =
                [[UINavigationController alloc] initWithRootViewController:viewController];
            [self.navigationController presentViewController:navigationController animated:YES completion:nil];
        }
    });
}

- (void)showErrorAlertForAttachment:(SignalAttachment * _Nullable)attachment {
    OWSAssert(attachment == nil || [attachment hasError]);
    
    NSString *errorMessage = (attachment
                              ? [attachment localizedErrorDescription]
                              : [SignalAttachment missingDataErrorMessage]);
    
    DDLogError(@"%@ %s: %@",
               self.tag,
               __PRETTY_FUNCTION__, errorMessage);
    
    UIAlertController *controller =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"ATTACHMENT_ERROR_ALERT_TITLE",
                                                                  @"The title of the 'attachment error' alert.")
                                        message:errorMessage
                                 preferredStyle:UIAlertControllerStyleAlert];
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                   style:UIAlertActionStyleDefault
                                                 handler:nil]];
    [self presentViewController:controller
                       animated:YES
                     completion:nil];
}

#pragma mark - OWSMessagesToolbarContentDelegate

- (void)voiceMemoGestureDidStart
{
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"voiceMemoGestureDidStart");

    [((OWSMessagesInputToolbar *)self.inputToolbar)showVoiceMemoUI];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    [self startRecordingVoiceMemo];
}

- (void)voiceMemoGestureDidEnd
{
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"voiceMemoGestureDidEnd");

    [((OWSMessagesInputToolbar *)self.inputToolbar) hideVoiceMemoUI:YES];
    [self endRecordingVoiceMemo];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)voiceMemoGestureDidCancel
{
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"voiceMemoGestureDidCancel");

    [((OWSMessagesInputToolbar *)self.inputToolbar) hideVoiceMemoUI:NO];
    [self cancelRecordingVoiceMemo];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)voiceMemoGestureDidChange:(CGFloat)cancelAlpha
{
    OWSAssert([NSThread isMainThread]);

    [((OWSMessagesInputToolbar *)self.inputToolbar) setVoiceMemoUICancelAlpha:cancelAlpha];
}

- (void)cancelVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

    [((OWSMessagesToolbarContentView *)self.inputToolbar.contentView)cancelVoiceMemoIfNecessary];
    [((OWSMessagesInputToolbar *)self.inputToolbar) hideVoiceMemoUI:NO];
    [self cancelRecordingVoiceMemo];
}

- (void)textViewDidChange:(UITextView *)textView
{
    // Override.
    //
    // We want to show the "voice message" button if the text input is empty
    // and the "send" button if it isn't.
    [((OWSMessagesToolbarContentView *)self.inputToolbar.contentView)ensureEnabling];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    self.userHasScrolled = YES;
}

#pragma mark - OWSConversationSettingsViewDelegate

- (void)groupWasUpdated:(TSGroupModel *)groupModel
{
    OWSAssert(groupModel);

    NSMutableSet *groupMemberIds = [NSMutableSet setWithArray:groupModel.groupMemberIds];
    [groupMemberIds addObject:[TSAccountManager localNumber]];
    groupModel.groupMemberIds = [NSMutableArray arrayWithArray:[groupMemberIds allObjects]];
    [self updateGroupModelTo:groupModel];
    [self.collectionView.collectionViewLayout
        invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
    [self.collectionView reloadData];
}

- (void)popAllConversationSettingsViews
{
    if (self.presentedViewController) {
        [self.presentedViewController
            dismissViewControllerAnimated:YES
                               completion:^{
                                   [self.navigationController popToViewController:self animated:YES];
                               }];
    } else {
        [self.navigationController popToViewController:self animated:YES];
    }
}

#pragma mark - Class methods

+ (UINib *)nib
{
    return [UINib nibWithNibName:NSStringFromClass([MessagesViewController class])
                          bundle:[NSBundle bundleForClass:[MessagesViewController class]]];
}

+ (instancetype)messagesViewController
{
    return [[[self class] alloc] initWithNibName:NSStringFromClass([MessagesViewController class])
                                          bundle:[NSBundle bundleForClass:[MessagesViewController class]]];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
