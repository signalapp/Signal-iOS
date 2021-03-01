//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SharingThreadPickerViewController.h"
#import "SignalApp.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <PromiseKit/PromiseKit.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SessionUtilitiesKit/NSString+SSK.h>
#import <SignalUtilitiesKit/OWSError.h>
#import <SessionMessagingKit/SessionMessagingKit.h>
#import <SessionUIKit/SessionUIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SendCompletionBlock)(NSError *_Nullable, TSOutgoingMessage *);
typedef void (^SendMessageBlock)(SendCompletionBlock completion);

@interface SharingThreadPickerViewController () <SelectThreadViewControllerDelegate,
    AttachmentApprovalViewControllerDelegate,
    MessageApprovalViewControllerDelegate>

@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic) TSThread *thread;
@property (nonatomic, readonly, weak) id<ShareViewDelegate> shareViewDelegate;
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

    _shareViewDelegate = shareViewDelegate;
    self.selectThreadViewDelegate = self;

    return self;
}

#pragma mark - Dependencies

- (YapDatabaseConnection *)dbReadWriteConnection
{
    return OWSPrimaryStorage.sharedManager.dbReadWriteConnection;
}

- (YapDatabaseConnection *)dbReadConnection
{
    return OWSPrimaryStorage.sharedManager.dbReadConnection;
}

#pragma mark - UIViewController overrides

- (void)loadView
{
    [super loadView];

    self.title = NSLocalizedString(@"SHARE_EXTENSION_VIEW_TITLE", @"Title for the 'share extension' view.");
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Loki: Customize title
    UILabel *titleLabel = [UILabel new];
    titleLabel.text = NSLocalizedString(@"Share", @"");
    titleLabel.textColor = LKColors.text;
    titleLabel.font = [UIFont boldSystemFontOfSize:25];
    self.navigationItem.titleView = titleLabel;
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
    header.backgroundColor = LKColors.navigationBarBackground;
    
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
    if (self.attachments.count > 1) {
        return nil;
    }
    OWSAssertDebug(self.attachments.count == 1);
    SignalAttachment *attachment = self.attachments.firstObject;
    if (!attachment.isConvertibleToTextMessage) {
        return nil;
    }
    if (attachment.dataLength >= kOversizeTextMessageSizeThreshold) {
        return nil;
    }
    NSData *data = attachment.data;
    OWSAssertDebug(data.length < kOversizeTextMessageSizeThreshold);
    NSString *_Nullable messageText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    OWSLogVerbose(@"messageTextForAttachment: %@", messageText);
    return [messageText filterStringForDisplay];
}

- (void)threadWasSelected:(TSThread *)thread
{
    OWSAssertDebug(self.attachments.count > 0);
    OWSAssertDebug(thread);

    self.thread = thread;

    if ([self tryToShareAsMessageText]) {
        return;
    }

    OWSNavigationController *approvalModal =
        [AttachmentApprovalViewController wrappedInNavControllerWithAttachments:self.attachments approvalDelegate:self];
    [self presentViewController:approvalModal animated:YES completion:nil];
}

- (BOOL)tryToShareAsMessageText
{
    OWSAssertDebug(self.attachments.count > 0);

    NSString *_Nullable messageText = [self convertAttachmentToMessageTextIfPossible];
    if (!messageText) {
        return NO;
    }

    MessageApprovalViewController *approvalVC =
        [[MessageApprovalViewController alloc] initWithMessageText:messageText
                                                            thread:self.thread
                                                          delegate:self];

    [self.navigationController pushViewController:approvalVC animated:YES];
    return YES;
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

- (void)attachmentApproval:(AttachmentApprovalViewController *_Nonnull)attachmentApproval
     didApproveAttachments:(NSArray<SignalAttachment *> *_Nonnull)attachments
               messageText:(NSString *_Nullable)messageText
{
    [self tryToSendMessageWithBlock:^(SendCompletionBlock sendCompletion) {
        SNVisibleMessage *message = [SNVisibleMessage new];
        message.sentTimestamp = [NSDate millisecondTimestamp];
        message.text = messageText;
        TSOutgoingMessage *tsMessage = [TSOutgoingMessage from:message associatedWith:self.thread];
        [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [tsMessage saveWithTransaction:transaction];
        }];
        [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [SNMessageSender sendNonDurably:message withAttachments:attachments inThread:self.thread usingTransaction:transaction]
            .then(^(id object) {
                sendCompletion(nil, tsMessage);
            }).catch(^(NSError *error) {
                sendCompletion(error, tsMessage);
            });
        }];

        // This is necessary to show progress
        self.outgoingMessage = tsMessage;
    } fromViewController:attachmentApproval];
}

- (void)attachmentApprovalDidCancel:(AttachmentApprovalViewController *)attachmentApproval
{
    [self cancelShareExperience];
}

- (void)attachmentApproval:(AttachmentApprovalViewController *)attachmentApproval
      didChangeMessageText:(nullable NSString *)newMessageText
{
    // no-op
}

#pragma mark - MessageApprovalViewControllerDelegate

- (void)messageApproval:(MessageApprovalViewController *)approvalViewController
      didApproveMessage:(NSString *)messageText
{
    [self tryToSendMessageWithBlock:^(SendCompletionBlock sendCompletion) {
        SNVisibleMessage *message = [SNVisibleMessage new];
        message.sentTimestamp = [NSDate millisecondTimestamp];
        message.text = messageText;
        TSOutgoingMessage *tsMessage = [TSOutgoingMessage from:message associatedWith:self.thread];
        [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [tsMessage saveWithTransaction:transaction];
        }];
        [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [SNMessageSender sendNonDurably:message withAttachments:@[] inThread:self.thread usingTransaction:transaction]
            .then(^(id object) {
                sendCompletion(nil, tsMessage);
            }).catch(^(NSError *error) {
                sendCompletion(error, tsMessage);
            });
        }];
        
        // This is necessary to show progress
        self.outgoingMessage = tsMessage;
    } fromViewController:approvalViewController];
}

- (void)messageApprovalDidCancel:(MessageApprovalViewController *)approvalViewController
{
    [self cancelShareExperience];
}

#pragma mark - Helpers

- (void)tryToSendMessageWithBlock:(SendMessageBlock)sendMessageBlock
               fromViewController:(UIViewController *)fromViewController
{

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

    SendCompletionBlock sendCompletion = ^(NSError *_Nullable error, TSOutgoingMessage *message) {

        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [fromViewController
                    dismissViewControllerAnimated:YES
                                       completion:^{
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

    [fromViewController presentAlert:progressAlert
                          completion:^{
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

        SNContactContext context = [SNContact contextForThread:self.thread];
        NSString *displayName = [[LKStorage.shared getContactWithSessionID:untrustedRecipientId] displayNameFor:context] ?: untrustedRecipientId;
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

        [fromViewController presentAlert:failureAlert];
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
        [fromViewController presentAlert:failureAlert];
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

    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [self resendMessage:message fromViewController:fromViewController];
    });
}

- (void)resendMessage:(TSOutgoingMessage *)tsMessage fromViewController:(UIViewController *)fromViewController
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(tsMessage);
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
        presentAlert:progressAlert
            completion:^{
                SNVisibleMessage *message = [SNVisibleMessage from:tsMessage];
                [LKStorage writeWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                    NSMutableArray<TSAttachmentStream *> *attachments = @[].mutableCopy;
                    for (NSString *attachmentID in tsMessage.attachmentIds) {
                        TSAttachmentStream *stream = [TSAttachmentStream fetchObjectWithUniqueID:attachmentID transaction:transaction];
                        if (![stream isKindOfClass:TSAttachmentStream.class]) { continue; }
                        [attachments addObject:stream];
                    }
                    [SNMessageSender prep:attachments forMessage:message usingTransaction: transaction];
                    [SNMessageSender sendNonDurably:message withAttachmentIDs:tsMessage.attachmentIds inThread:self.thread usingTransaction:transaction]
                    .thenOn(dispatch_get_main_queue(), ^() {
                        [self.shareViewDelegate shareViewWasCompleted];
                    })
                    .catchOn(dispatch_get_main_queue(), ^(NSError *error) {
                        [fromViewController dismissViewControllerAnimated:YES completion:^{
                            [self showSendFailureAlertWithError:error message:tsMessage fromViewController:fromViewController];
                        }];
                    });
                }];
          }];
}

@end

NS_ASSUME_NONNULL_END
