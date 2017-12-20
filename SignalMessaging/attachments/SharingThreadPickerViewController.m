//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
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
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface SharingThreadPickerViewController () <SelectThreadViewControllerDelegate,
    AttachmentApprovalViewControllerDelegate>

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic) TSThread *thread;
@property (nonatomic, readonly, weak) id<ShareViewDelegate> shareViewDelegate;
@property (nonatomic, readonly) UIProgressView *progressView;
@property (nullable, atomic) TSOutgoingMessage *outgoingMessage;

@end

#pragma mark -

@implementation SharingThreadPickerViewController

- (instancetype)initWithShareViewDelegate:(id<ShareViewDelegate>)shareViewDelegate;
{
    self = [super init];
    if (!self) {
        return self;
    }

    _shareViewDelegate = shareViewDelegate;
    self.selectThreadViewDelegate = self;

    return self;
}

- (void)loadView
{
    [super loadView];

    _contactsManager = [Environment current].contactsManager;
    _messageSender = [Environment current].messageSender;

    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.title = NSLocalizedString(@"SEND_EXTERNAL_FILE_VIEW_TITLE", @"Title for the 'send external file' view.");
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
    OWSAssert(searchBar)

        const CGFloat contentVMargin
        = 0;

    UIView *header = [UIView new];
    header.backgroundColor = [UIColor whiteColor];

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

- (void)threadWasSelected:(TSThread *)thread
{
    OWSAssert(self.attachment);
    OWSAssert(thread);
    self.thread = thread;

    __weak typeof(self) weakSelf = self;

    // FIXME SHARINGEXTENSION
    // Handling safety number changes brings in a lot of machinery.
    // How do we want to handle this?
    // e.g. fingerprint scanning, etc. in the SAE or just redirect the user to the main app?
    //    BOOL didShowSNAlert =
    //        [SafetyNumberConfirmationAlert presentAlertIfNecessaryWithRecipientIds:thread.recipientIdentifiers
    //                                                              confirmationText:[SafetyNumberStrings
    //                                                              confirmSendButton]
    //                                                               contactsManager:self.contactsManager
    //                                                                    completion:^(BOOL didConfirm) {
    //                                                                        if (didConfirm) {
    //                                                                            [weakSelf threadWasSelected:thread];
    //                                                                        }
    //                                                                    }];
    //    if (didShowSNAlert) {
    //        return;
    //    }

    AttachmentApprovalViewController *approvalVC =
        [[AttachmentApprovalViewController alloc] initWithAttachment:self.attachment delegate:self];

    [self.navigationController pushViewController:approvalVC animated:YES];
}

- (void)didTapCancelShareButton
{
    DDLogDebug(@"%@ tapped cancel share button", self.logTag);
    [self cancelShareExperience];
}

- (void)cancelShareExperience
{
    [self.shareViewDelegate shareViewWasCancelled];
}

#pragma mark - AttachmentApprovalViewControllerDelegate

- (void)attachmentApproval:(AttachmentApprovalViewController *)attachmentApproval
      didApproveAttachment:(SignalAttachment *)attachment
{
    [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];
    [self tryToSendAttachment:attachment fromViewController:attachmentApproval];
}

- (void)attachmentApproval:(AttachmentApprovalViewController *)attachmentApproval
       didCancelAttachment:(SignalAttachment *)attachment
{
    [self cancelShareExperience];
}

#pragma mark - Helpers

- (void)tryToSendAttachment:(SignalAttachment *)attachment fromViewController:(UIViewController *)fromViewController
{
    // Reset progress in case we're retrying
    self.progressView.progress = 0;

    self.attachment = attachment;

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


    // Adding a subview to the alert controller like this is a total hack.
    // ...but it looks good, and given how short a progress view is and how
    // little the alert controller changes, I'm not super worried about it.
#ifdef DEBUG
    if (@available(iOS 12, *)) {
        // Congratulations! You survived to see another iOS release.
        OWSFail(@"Make sure progress view still looks good increment this version canary.");
    }
#endif
    [progressAlert.view addSubview:self.progressView];
    [self.progressView autoPinWidthToSuperviewWithMargin:24];
    [self.progressView autoAlignAxis:ALAxisHorizontal toSameAxisOfView:progressAlert.view withOffset:4];

    void (^presentRetryDialog)(NSError *error) = ^(NSError *error) {
        [fromViewController
            dismissViewControllerAnimated:YES
                               completion:^(void) {
                                   AssertIsOnMainThread();
                                   NSString *failureTitle
                                       = NSLocalizedString(@"SHARE_EXTENSION_SENDING_FAILURE_TITLE", @"Alert title");

                                   UIAlertController *failureAlert =
                                       [UIAlertController alertControllerWithTitle:failureTitle
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];

                                   UIAlertAction *failureCancelAction =
                                       [UIAlertAction actionWithTitle:[CommonStrings cancelButton]
                                                                style:UIAlertActionStyleCancel
                                                              handler:^(UIAlertAction *_Nonnull action) {
                                                                  [self.shareViewDelegate shareViewWasCancelled];
                                                              }];
                                   [failureAlert addAction:failureCancelAction];

                                   UIAlertAction *retryAction =
                                       [UIAlertAction actionWithTitle:[CommonStrings retryButton]
                                                                style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction *action) {
                                                                  [self tryToSendAttachment:attachment
                                                                         fromViewController:fromViewController];
                                                              }];
                                   [failureAlert addAction:retryAction];

                                   [fromViewController presentViewController:failureAlert animated:YES completion:nil];
                               }];
    };

    void (^sendCompletion)(NSError *_Nullable) = ^(NSError *_Nullable error) {
        AssertIsOnMainThread();

        if (error) {
            DDLogInfo(@"%@ Sending attachment failed with error: %@", self.logTag, error);
            presentRetryDialog(error);
            return;
        }

        DDLogInfo(@"%@ Sending attachment succeeded.", self.logTag);
        [self.shareViewDelegate shareViewWasCompleted];
    };

    [fromViewController presentViewController:progressAlert
                                     animated:YES
                                   completion:^(void) {
                                       TSOutgoingMessage *outgoingMessage =
                                           [ThreadUtil sendMessageWithAttachment:self.attachment
                                                                        inThread:self.thread
                                                                   messageSender:self.messageSender
                                                                      completion:sendCompletion];

                                       self.outgoingMessage = outgoingMessage;
                                   }];
}

- (void)attachmentUploadProgress:(NSNotification *)notification
{
    DDLogDebug(@"%@ upload progress.", self.logTag);
    AssertIsOnMainThread();
    OWSAssert(self.progressView);

    if (!self.outgoingMessage) {
        DDLogDebug(@"%@ Ignoring upload progress until there is an outgoing message.", self.logTag);
        return;
    }

    NSString *attachmentRecordId = self.outgoingMessage.attachmentIds.firstObject;
    if (!attachmentRecordId) {
        DDLogDebug(@"%@ Ignoring upload progress until outgoing message has an attachment record id", self.logTag);
        return;
    }

    NSDictionary *userinfo = [notification userInfo];
    float progress = [[userinfo objectForKey:kAttachmentUploadProgressKey] floatValue];
    NSString *attachmentID = [userinfo objectForKey:kAttachmentUploadAttachmentIDKey];

    if ([attachmentRecordId isEqual:attachmentID]) {
        if (!isnan(progress)) {
            [self.progressView setProgress:progress animated:YES];
        } else {
            OWSFail(@"%@ Invalid attachment progress.", self.logTag);
        }
    }
}

@end

NS_ASSUME_NONNULL_END
