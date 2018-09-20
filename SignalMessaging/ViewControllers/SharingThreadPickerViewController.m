//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SharingThreadPickerViewController.h"
#import "Environment.h"
#import "NSString+OWS.h"
#import "SignalApp.h"
#import "ThreadUtil.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SendCompletionBlock)(NSError *_Nullable, TSOutgoingMessage *);
typedef void (^SendMessageBlock)(SendCompletionBlock completion);

@interface SharingThreadPickerViewController () <SelectThreadViewControllerDelegate,
    AttachmentApprovalViewControllerDelegate,
    MessageApprovalViewControllerDelegate,
    ContactShareApprovalViewControllerDelegate>

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic) TSThread *thread;
@property (nonatomic, readonly, weak) id<ShareViewDelegate> shareViewDelegate;
@property (nonatomic, readonly) UIProgressView *progressView;
@property (nonatomic, readonly) YapDatabaseConnection *editingDBConnection;
@property (atomic, nullable) TSOutgoingMessage *outgoingMessage;

@end

#pragma mark -

@implementation SharingThreadPickerViewController

- (instancetype)initWithShareViewDelegate:(id<ShareViewDelegate>)shareViewDelegate
{
    self = [super init];
    if (!self) {
        return self;
    }

    _editingDBConnection = [OWSPrimaryStorage.sharedManager newDatabaseConnection];
    _shareViewDelegate = shareViewDelegate;
    self.selectThreadViewDelegate = self;

    return self;
}

- (void)loadView
{
    [super loadView];

    _contactsManager = Environment.shared.contactsManager;
    _messageSender = SSKEnvironment.shared.messageSender;

    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.title = NSLocalizedString(@"SHARE_EXTENSION_VIEW_TITLE", @"Title for the 'share extension' view.");
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(attachmentUploadProgress:)
                                                 name:kAttachmentUploadProgressNotification
                                               object:nil];
}

- (BOOL)canSelectBlockedContact
{
    return NO;
}

- (nullable UIView *)createHeaderWithSearchBar:(UISearchBar *)searchBar
{
    OWSAssertDebug(searchBar);

    const CGFloat contentVMargin = 0;

    UIView *header = [UIView new];
    header.backgroundColor = Theme.backgroundColor;

    UIButton *cancelShareButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [header addSubview:cancelShareButton];

    [cancelShareButton setTitle:[CommonStrings cancelButton] forState:UIControlStateNormal];
    cancelShareButton.userInteractionEnabled = YES;

    [cancelShareButton autoPinEdgeToSuperviewMargin:ALEdgeLeading];
    [cancelShareButton autoPinEdgeToSuperviewMargin:ALEdgeBottom];
    [cancelShareButton setCompressionResistanceHigh];
    [cancelShareButton setContentHuggingHigh];

    [cancelShareButton addTarget:self
                          action:@selector(didTapCancelShareButton)
                forControlEvents:UIControlEventTouchUpInside];

    [header addSubview:searchBar];
    [searchBar autoPinEdge:ALEdgeLeading toEdge:ALEdgeTrailing ofView:cancelShareButton withOffset:6];
    [searchBar autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    [searchBar autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [searchBar autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    UIView *borderView = [UIView new];
    [header addSubview:borderView];

    borderView.backgroundColor = [UIColor colorWithRGBHex:0xbbbbbb];
    [borderView autoSetDimension:ALDimensionHeight toSize:0.5];
    [borderView autoPinWidthToSuperview];
    [borderView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    // UITableViewController.tableHeaderView must have its height set.
    header.frame = CGRectMake(0, 0, 0, (contentVMargin * 2 + searchBar.frame.size.height));

    return header;
}

#pragma mark - SelectThreadViewControllerDelegate

- (nullable NSString *)convertAttachmentToMessageTextIfPossible
{
    if (!self.attachment.isConvertibleToTextMessage) {
        return nil;
    }
    if (self.attachment.dataLength >= kOversizeTextMessageSizeThreshold) {
        return nil;
    }
    NSData *data = self.attachment.data;
    OWSAssertDebug(data.length < kOversizeTextMessageSizeThreshold);
    NSString *_Nullable messageText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    OWSLogVerbose(@"messageTextForAttachment: %@", messageText);
    return [messageText filterStringForDisplay];
}

- (void)threadWasSelected:(TSThread *)thread
{
    OWSAssertDebug(self.attachment);
    OWSAssertDebug(thread);

    self.thread = thread;

    if (self.attachment.isConvertibleToContactShare) {
        [self showContactShareApproval];
        return;
    }

    NSString *_Nullable messageText = [self convertAttachmentToMessageTextIfPossible];

    if (messageText) {
        MessageApprovalViewController *approvalVC =
            [[MessageApprovalViewController alloc] initWithMessageText:messageText
                                                                thread:thread
                                                       contactsManager:self.contactsManager
                                                              delegate:self];

        [self.navigationController pushViewController:approvalVC animated:YES];
    } else {
        OWSNavigationController *approvalModal =
            [AttachmentApprovalViewController wrappedInNavControllerWithAttachment:self.attachment delegate:self];
        [self presentViewController:approvalModal animated:YES completion:nil];
    }
}

- (void)showContactShareApproval
{
    OWSAssertDebug(self.attachment);
    OWSAssertDebug(self.thread);
    OWSAssertDebug(self.attachment.isConvertibleToContactShare);

    NSData *data = self.attachment.data;

    CNContact *_Nullable cnContact = [Contact cnContactWithVCardData:data];
    Contact *_Nullable contact = [[Contact alloc] initWithSystemContact:cnContact];
    OWSContact *_Nullable contactShareRecord = [OWSContacts contactForSystemContact:cnContact];
    if (!contactShareRecord) {
        OWSLogError(@"Could not convert system contact.");
        return;
    }

    BOOL isProfileAvatar = NO;
    NSData *_Nullable avatarImageData = [self.contactsManager avatarDataForCNContactId:contact.cnContactId];
    for (NSString *recipientId in contact.textSecureIdentifiers) {
        if (avatarImageData) {
            break;
        }
        avatarImageData = [self.contactsManager profileImageDataForPhoneIdentifier:recipientId];
        if (avatarImageData) {
            isProfileAvatar = YES;
        }
    }
    contactShareRecord.isProfileAvatar = isProfileAvatar;

    ContactShareViewModel *contactShare =
        [[ContactShareViewModel alloc] initWithContactShareRecord:contactShareRecord avatarImageData:avatarImageData];

    ContactShareApprovalViewController *approvalVC =
        [[ContactShareApprovalViewController alloc] initWithContactShare:contactShare
                                                         contactsManager:self.contactsManager
                                                                delegate:self];
    [self.navigationController pushViewController:approvalVC animated:YES];
}

// override
- (void)dismissPressed:(id)sender
{
    OWSLogDebug(@"tapped dismiss share button");
    [self cancelShareExperience];
}

- (void)didTapCancelShareButton
{
    OWSLogDebug(@"tapped cancel share button");
    [self cancelShareExperience];
}

- (void)cancelShareExperience
{
    [self.shareViewDelegate shareViewWasCancelled];
}

#pragma mark - AttachmentApprovalViewControllerDelegate

- (void)attachmentApproval:(AttachmentApprovalViewController *)approvalViewController
      didApproveAttachment:(SignalAttachment *)attachment
{
    [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];
    [self tryToSendMessageWithBlock:^(SendCompletionBlock sendCompletion) {
        OWSAssertIsOnMainThread();

        __block TSOutgoingMessage *outgoingMessage = nil;
        outgoingMessage = [ThreadUtil sendMessageWithAttachment:attachment
                                                       inThread:self.thread
                                               quotedReplyModel:nil
                                                  messageSender:self.messageSender
                                                     completion:^(NSError *_Nullable error) {
                                                         sendCompletion(error, outgoingMessage);
                                                     }];

        // This is necessary to show progress.
        self.outgoingMessage = outgoingMessage;
    }
                 fromViewController:approvalViewController];
}

- (void)attachmentApproval:(AttachmentApprovalViewController *)attachmentApproval
       didCancelAttachment:(SignalAttachment *)attachment
{
    [self cancelShareExperience];
}

#pragma mark - MessageApprovalViewControllerDelegate

- (void)messageApproval:(MessageApprovalViewController *)approvalViewController
      didApproveMessage:(NSString *)messageText
{
    OWSAssertDebug(messageText.length > 0);

    [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];
    [self tryToSendMessageWithBlock:^(SendCompletionBlock sendCompletion) {
        OWSAssertIsOnMainThread();

        __block TSOutgoingMessage *outgoingMessage = nil;
        outgoingMessage = [ThreadUtil sendMessageWithText:messageText
            inThread:self.thread
            quotedReplyModel:nil
            messageSender:self.messageSender
            success:^{
                sendCompletion(nil, outgoingMessage);
            }
            failure:^(NSError *_Nonnull error) {
                sendCompletion(error, outgoingMessage);
            }];

        // This is necessary to show progress.
        self.outgoingMessage = outgoingMessage;
    }
                 fromViewController:approvalViewController];
}

- (void)messageApprovalDidCancel:(MessageApprovalViewController *)approvalViewController
{
    [self cancelShareExperience];
}

#pragma mark - ContactShareApprovalViewControllerDelegate

- (void)approveContactShare:(ContactShareApprovalViewController *)approvalViewController
     didApproveContactShare:(ContactShareViewModel *)contactShare
{
    OWSLogInfo(@"");

    [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];
    [self tryToSendMessageWithBlock:^(SendCompletionBlock sendCompletion) {
        OWSAssertIsOnMainThread();
        [self.editingDBConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            if (contactShare.avatarImage) {
                [contactShare.dbRecord saveAvatarImage:contactShare.avatarImage transaction:transaction];
            }
        }
            completionBlock:^{
                __block TSOutgoingMessage *outgoingMessage = nil;
                outgoingMessage = [ThreadUtil sendMessageWithContactShare:contactShare.dbRecord
                                                                 inThread:self.thread
                                                            messageSender:self.messageSender
                                                               completion:^(NSError *_Nullable error) {
                                                                   sendCompletion(error, outgoingMessage);
                                                               }];
                // This is necessary to show progress.
                self.outgoingMessage = outgoingMessage;
            }];
                                                    
        
    }
                 fromViewController:approvalViewController];
}

- (void)approveContactShare:(ContactShareApprovalViewController *)approvalViewController
      didCancelContactShare:(ContactShareViewModel *)contactShare
{
    OWSLogInfo(@"");

    [self cancelShareExperience];
}

#pragma mark - Helpers

- (void)tryToSendMessageWithBlock:(SendMessageBlock)sendMessageBlock
               fromViewController:(UIViewController *)fromViewController
{
    // Reset progress in case we're retrying
    self.progressView.progress = 0;

    NSString *progressTitle = NSLocalizedString(@"SHARE_EXTENSION_SENDING_IN_PROGRESS_TITLE", @"Alert title");
    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:progressTitle
                                                                           message:nil
                                                                    preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *progressCancelAction = [UIAlertAction actionWithTitle:[CommonStrings cancelButton]
                                                                   style:UIAlertActionStyleCancel
                                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                                     [self.shareViewDelegate shareViewWasCancelled];
                                                                 }];
    [progressAlert addAction:progressCancelAction];


    // We add a progress subview to an AlertController, which is a total hack.
    // ...but it looks good, and given how short a progress view is and how
    // little the alert controller changes, I'm not super worried about it.
    [progressAlert.view addSubview:self.progressView];
    [self.progressView autoPinWidthToSuperviewWithMargin:24];
    [self.progressView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:progressAlert.view withOffset:4];
#ifdef DEBUG
    if (@available(iOS 12, *)) {
        // TODO: Congratulations! You survived to see another iOS release.
        OWSFailDebug(@"Make sure the progress view still looks good, and increment the version canary.");
    }
#endif

    SendCompletionBlock sendCompletion = ^(NSError *_Nullable error, TSOutgoingMessage *message) {

        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [fromViewController
                    dismissViewControllerAnimated:YES
                                       completion:^(void) {
                                           OWSLogInfo(@"Sending message failed with error: %@", error);
                                           [self showSendFailureAlertWithError:error
                                                                       message:message
                                                            fromViewController:fromViewController];
                                       }];
                return;
            }

            OWSLogInfo(@"Sending message succeeded.");
            [self.shareViewDelegate shareViewWasCompleted];
        });
    };

    [fromViewController presentViewController:progressAlert
                                     animated:YES
                                   completion:^(void) {
                                       sendMessageBlock(sendCompletion);
                                   }];
}

- (void)showSendFailureAlertWithError:(NSError *)error
                              message:(TSOutgoingMessage *)message
                   fromViewController:(UIViewController *)fromViewController
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(error);
    OWSAssertDebug(message);
    OWSAssertDebug(fromViewController);

    NSString *failureTitle = NSLocalizedString(@"SHARE_EXTENSION_SENDING_FAILURE_TITLE", @"Alert title");

    if ([error.domain isEqual:OWSSignalServiceKitErrorDomain] && error.code == OWSErrorCodeUntrustedIdentity) {
        NSString *_Nullable untrustedRecipientId = error.userInfo[OWSErrorRecipientIdentifierKey];

        NSString *failureFormat = NSLocalizedString(@"SHARE_EXTENSION_FAILED_SENDING_BECAUSE_UNTRUSTED_IDENTITY_FORMAT",
            @"alert body when sharing file failed because of untrusted/changed identity keys");

        NSString *displayName = [self.contactsManager displayNameForPhoneIdentifier:untrustedRecipientId];
        NSString *failureMessage = [NSString stringWithFormat:failureFormat, displayName];

        UIAlertController *failureAlert = [UIAlertController alertControllerWithTitle:failureTitle
                                                                              message:failureMessage
                                                                       preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *failureCancelAction = [UIAlertAction actionWithTitle:[CommonStrings cancelButton]
                                                                      style:UIAlertActionStyleCancel
                                                                    handler:^(UIAlertAction *_Nonnull action) {
                                                                        [self.shareViewDelegate shareViewWasCancelled];
                                                                    }];
        [failureAlert addAction:failureCancelAction];

        if (untrustedRecipientId.length > 0) {
            UIAlertAction *confirmAction =
                [UIAlertAction actionWithTitle:[SafetyNumberStrings confirmSendButton]
                                         style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action) {
                                           [self confirmIdentityAndResendMessage:message
                                                                     recipientId:untrustedRecipientId
                                                              fromViewController:fromViewController];
                                       }];

            [failureAlert addAction:confirmAction];
        } else {
            // This shouldn't happen, but if it does we won't offer the user the ability to confirm.
            // They may have to return to the main app to accept the identity change.
            OWSFailDebug(@"Untrusted recipient error is missing recipient id.");
        }

        [fromViewController presentViewController:failureAlert animated:YES completion:nil];
    } else {
        // Non-identity failure, e.g. network offline, rate limit

        UIAlertController *failureAlert = [UIAlertController alertControllerWithTitle:failureTitle
                                                                              message:error.localizedDescription
                                                                       preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *failureCancelAction = [UIAlertAction actionWithTitle:[CommonStrings cancelButton]
                                                                      style:UIAlertActionStyleCancel
                                                                    handler:^(UIAlertAction *_Nonnull action) {
                                                                        [self.shareViewDelegate shareViewWasCancelled];
                                                                    }];
        [failureAlert addAction:failureCancelAction];

        UIAlertAction *retryAction =
            [UIAlertAction actionWithTitle:[CommonStrings retryButton]
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *action) {
                                       [self resendMessage:message fromViewController:fromViewController];
                                   }];

        [failureAlert addAction:retryAction];
        [fromViewController presentViewController:failureAlert animated:YES completion:nil];
    }
}

- (void)confirmIdentityAndResendMessage:(TSOutgoingMessage *)message
                            recipientId:(NSString *)recipientId
                     fromViewController:(UIViewController *)fromViewController
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(message);
    OWSAssertDebug(recipientId.length > 0);
    OWSAssertDebug(fromViewController);

    OWSLogDebug(@"Confirming identity for recipient: %@", recipientId);

    [OWSPrimaryStorage.sharedManager.newDatabaseConnection asyncReadWriteWithBlock:^(
        YapDatabaseReadWriteTransaction *transaction) {
        OWSVerificationState verificationState =
            [[OWSIdentityManager sharedManager] verificationStateForRecipientId:recipientId transaction:transaction];
        switch (verificationState) {
            case OWSVerificationStateVerified: {
                OWSFailDebug(@"Shouldn't need to confirm identity if it was already verified");
                break;
            }
            case OWSVerificationStateDefault: {
                // If we learned of a changed SN during send, then we've already recorded the new identity
                // and there's nothing else we need to do for the resend to succeed.
                // We don't want to redundantly set status to "default" because we would create a
                // "You marked Alice as unverified" notice, which wouldn't make sense if Alice was never
                // marked as "Verified".
                OWSLogInfo(@"recipient has acceptable verification status. Next send will succeed.");
                break;
            }
            case OWSVerificationStateNoLongerVerified: {
                OWSLogInfo(@"marked recipient: %@ as default verification status.", recipientId);
                NSData *identityKey =
                    [[OWSIdentityManager sharedManager] identityKeyForRecipientId:recipientId transaction:transaction];
                OWSAssertDebug(identityKey);
                [[OWSIdentityManager sharedManager] setVerificationState:OWSVerificationStateDefault
                                                             identityKey:identityKey
                                                             recipientId:recipientId
                                                   isUserInitiatedChange:YES
                                                             transaction:transaction];
                break;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^(void) {
            [self resendMessage:message fromViewController:fromViewController];
        });
    }];
}

- (void)resendMessage:(TSOutgoingMessage *)message fromViewController:(UIViewController *)fromViewController
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(message);
    OWSAssertDebug(fromViewController);

    NSString *progressTitle = NSLocalizedString(@"SHARE_EXTENSION_SENDING_IN_PROGRESS_TITLE", @"Alert title");
    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:progressTitle
                                                                           message:nil
                                                                    preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *progressCancelAction = [UIAlertAction actionWithTitle:[CommonStrings cancelButton]
                                                                   style:UIAlertActionStyleCancel
                                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                                     [self.shareViewDelegate shareViewWasCancelled];
                                                                 }];
    [progressAlert addAction:progressCancelAction];

    [fromViewController
        presentViewController:progressAlert
                     animated:YES
                   completion:^(void) {
                       [self.messageSender enqueueMessage:message
                           success:^(void) {
                               OWSLogInfo(@"Resending attachment succeeded.");
                               dispatch_async(dispatch_get_main_queue(), ^(void) {
                                   [self.shareViewDelegate shareViewWasCompleted];
                               });
                           }
                           failure:^(NSError *error) {
                               dispatch_async(dispatch_get_main_queue(), ^(void) {
                                   [fromViewController
                                       dismissViewControllerAnimated:YES
                                                          completion:^(void) {
                                                              OWSLogInfo(
                                                                  @"Sending attachment failed with error: %@", error);
                                                              [self showSendFailureAlertWithError:error
                                                                                          message:message
                                                                               fromViewController:fromViewController];
                                                          }];
                               });
                           }];
                   }];
}

- (void)attachmentUploadProgress:(NSNotification *)notification
{
    OWSLogDebug(@"upload progress.");
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.progressView);

    if (!self.outgoingMessage) {
        OWSLogDebug(@"Ignoring upload progress until there is an outgoing message.");
        return;
    }

    NSString *_Nullable attachmentRecordId = self.outgoingMessage.attachmentIds.firstObject;
    if (!attachmentRecordId) {
        OWSLogDebug(@"Ignoring upload progress until outgoing message has an attachment record id");
        return;
    }

    NSDictionary *userinfo = [notification userInfo];
    float progress = [[userinfo objectForKey:kAttachmentUploadProgressKey] floatValue];
    NSString *attachmentID = [userinfo objectForKey:kAttachmentUploadAttachmentIDKey];

    if ([attachmentRecordId isEqual:attachmentID]) {
        if (!isnan(progress)) {
            [self.progressView setProgress:progress animated:YES];
        } else {
            OWSFailDebug(@"Invalid attachment progress.");
        }
    }
}

@end

NS_ASSUME_NONNULL_END
