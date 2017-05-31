//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessagesComposerTextView.h"
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
#import "Signal-Swift.h"
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
//#import "UIFont+OWS.h"
//#import "UIUtil.h"
//#import "UIViewController+CameraPermissions.h"
//#import "UIViewController+OWS.h"
//#import "ViewControllerUtils.h"
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
//#import <SignalServiceKit/NSTimer+OWS.h>
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
//
//@import Photos;
//
//// Always load up to 50 messages when user arrives.
// static const int kYapDatabasePageSize = 50;
//// Never show more than 50*50 = 2,500 messages in conversation view at a time.
// static const int kYapDatabaseMaxPageCount = 50;
//// Never show more than 6*50 = 300 messages in conversation view when user
//// arrives.
// static const int kYapDatabaseMaxInitialPageCount = 6;
// static const int kYapDatabaseRangeMaxLength = kYapDatabasePageSize * kYapDatabaseMaxPageCount;
// static const int kYapDatabaseRangeMinLength = 0;
// static const int JSQ_TOOLBAR_ICON_HEIGHT = 22;
// static const int JSQ_TOOLBAR_ICON_WIDTH = 22;
// static const int JSQ_IMAGE_INSET = 5;
//
// static NSTimeInterval const kTSMessageSentDateShowTimeInterval = 5 * 60;
//
// NSString *const OWSMessagesViewControllerDidAppearNotification = @"OWSMessagesViewControllerDidAppear";
//
// typedef enum : NSUInteger {
//    kMediaTypePicture,
//    kMediaTypeVideo,
//} kMediaTypes;
//
//#pragma mark -
//
//@interface OWSMessagesCollectionViewFlowLayout : JSQMessagesCollectionViewFlowLayout
//
//@property (nonatomic) CGRect lastBounds;
//
//

//
//#pragma mark -
//
//@implementation OWSMessagesCollectionViewFlowLayout
//
//- (void)prepareLayout
//{
//    [super prepareLayout];
//
//    DDLogError(@"----- OWSMessagesCollectionViewFlowLayout prepareLayout");
//}
//
////- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
////    BOOL result = self.lastBounds.size.width != newBounds.size.width;
////
////    DDLogError(@"----- OWSMessagesCollectionViewFlowLayout shouldInvalidat: %d, lastBounds: %@, newBounds: %@",
////    result,
////               NSStringFromCGRect(self.lastBounds),
////               NSStringFromCGRect(newBounds)
////               );
////
////    self.lastBounds = newBounds;
////
////    return result;
////}
//
//@end
//
//#pragma mark -

//@interface OWSMessagesComposerTextView ()
//
//@property (weak, nonatomic) id<OWSTextViewPasteDelegate> textViewPasteDelegate;
//
//@end
//
//#pragma mark -

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
