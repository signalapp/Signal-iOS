//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessagesInputToolbar.h"
#import "OWSMessagesToolbarContentView.h"
//#import "AppDelegate.h"
//#import "AttachmentSharing.h"
//#import "BlockListUIUtils.h"
//#import "BlockListViewController.h"
//#import "ContactsViewHelper.h"
//#import "DebugUITableViewController.h"
//#import "Environment.h"
//#import "FingerprintViewController.h"
//#import "FullImageViewController.h"
//#import "NSDate+millisecondTimeStamp.h"
//#import "NewGroupViewController.h"
//#import "OWSAudioAttachmentPlayer.h"
//#import "OWSCall.h"
//#import "OWSCallCollectionViewCell.h"
//#import "OWSContactsManager.h"
//#import "OWSConversationSettingsTableViewController.h"
//#import "OWSConversationSettingsViewDelegate.h"
//#import "OWSDisappearingMessagesJob.h"
//#import "OWSDisplayedMessageCollectionViewCell.h"
//#import "OWSExpirableMessageView.h"
//#import "OWSIncomingMessageCollectionViewCell.h"
//#import "OWSMessageCollectionViewCell.h"
//#import "OWSMessagesBubblesSizeCalculator.h"
//#import "OWSOutgoingMessageCollectionViewCell.h"
//#import "OWSUnreadIndicatorCell.h"
//#import "PropertyListPreferences.h"
//#import "Signal-Swift.h"
//#import "SignalKeyingStorage.h"
//#import "TSAttachmentPointer.h"
//#import "TSCall.h"
//#import "TSContactThread.h"
//#import "TSContentAdapters.h"
//#import "TSDatabaseView.h"
//#import "TSErrorMessage.h"
//#import "TSGenericAttachmentAdapter.h"
//#import "TSGroupThread.h"
//#import "TSIncomingMessage.h"
//#import "TSInfoMessage.h"
//#import "TSInvalidIdentityKeyErrorMessage.h"
//#import "TSUnreadIndicatorInteraction.h"
//#import "ThreadUtil.h"
//#import "UIUtil.h"
//#import "UIViewController+CameraPermissions.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
//#import "UIViewController+OWS.h"
#import "ViewControllerUtils.h"
//#import <AddressBookUI/AddressBookUI.h>
//#import <AssetsLibrary/AssetsLibrary.h>
//#import <ContactsUI/CNContactViewController.h>
//#import <JSQMessagesViewController/JSQMessagesBubbleImage.h>
//#import <JSQMessagesViewController/JSQMessagesBubbleImageFactory.h>
//#import <JSQMessagesViewController/JSQMessagesCollectionViewFlowLayoutInvalidationContext.h>
//#import <JSQMessagesViewController/JSQMessagesTimestampFormatter.h>
//#import <JSQMessagesViewController/JSQSystemSoundPlayer+JSQMessages.h>
//#import <JSQMessagesViewController/UIColor+JSQMessages.h>
//#import <JSQSystemSoundPlayer.h>
//#import <MobileCoreServices/UTCoreTypes.h>
//#import <SignalServiceKit/ContactsUpdater.h>
//#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/NSTimer+OWS.h>
//#import <SignalServiceKit/OWSAddToContactsOfferMessage.h>
//#import <SignalServiceKit/OWSAttachmentsProcessor.h>
//#import <SignalServiceKit/OWSBlockingManager.h>
//#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
//#import <SignalServiceKit/OWSFingerprint.h>
//#import <SignalServiceKit/OWSFingerprintBuilder.h>
//#import <SignalServiceKit/OWSMessageSender.h>
//#import <SignalServiceKit/OWSUnknownContactBlockOfferMessage.h>
//#import <SignalServiceKit/SignalRecipient.h>
//#import <SignalServiceKit/TSAccountManager.h>
//#import <SignalServiceKit/TSInvalidIdentityKeySendingErrorMessage.h>
//#import <SignalServiceKit/TSMessagesManager.h>
//#import <SignalServiceKit/TSNetworkManager.h>
//#import <SignalServiceKit/Threading.h>
//#import <YapDatabase/YapDatabaseView.h>

@interface OWSMessagesInputToolbar () <OWSSendMessageGestureDelegate>

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

- (JSQMessagesToolbarContentView *)loadToolbarContentView
{
    NSArray *views = [[OWSMessagesToolbarContentView nib] instantiateWithOwner:nil options:nil];
    OWSAssert(views.count == 1);
    OWSMessagesToolbarContentView *view = views[0];
    OWSAssert([view isKindOfClass:[OWSMessagesToolbarContentView class]]);
    view.sendMessageGestureDelegate = self;
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

#pragma mark - OWSSendMessageGestureDelegate

- (void)sendMessageGestureRecognized
{
    OWSAssert(self.sendButtonOnRight);
    [self.delegate messagesInputToolbar:self didPressRightBarButton:self.contentView.rightBarButtonItem];
}

@end
