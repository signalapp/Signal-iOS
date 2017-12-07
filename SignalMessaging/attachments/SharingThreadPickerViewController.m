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

    self.title = NSLocalizedString(@"SEND_EXTERNAL_FILE_VIEW_TITLE", @"Title for the 'send external file' view.");
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

- (void)didApproveAttachment
{
    [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];
    [ThreadUtil sendMessageWithAttachment:self.attachment inThread:self.thread messageSender:self.messageSender];

    // This is just a temporary hack while testing to hopefully not dismiss too early.
    // FIXME Show progress dialog
    // FIXME don't dismiss until sending is complete
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.shareViewDelegate shareViewWasCompleted];
    });
}

- (void)didCancelAttachment
{
    [self cancelShareExperience];
}

@end

NS_ASSUME_NONNULL_END
