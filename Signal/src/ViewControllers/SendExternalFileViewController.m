//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SendExternalFileViewController.h"
#import "Environment.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface SendExternalFileViewController () <SelectThreadViewControllerDelegate>

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSMessageSender *messageSender;

@end

#pragma mark -

@implementation SendExternalFileViewController

- (instancetype)init
{
    if (self = [super init]) {
        self.delegate = self;
    }
    return self;
}

- (void)loadView
{
    [super loadView];

    _contactsManager = [Environment getCurrent].contactsManager;
    _messageSender = [Environment getCurrent].messageSender;

    self.title = NSLocalizedString(@"SEND_EXTERNAL_FILE_VIEW_TITLE", @"Title for the 'send external file' view.");
}

#pragma mark - SelectThreadViewControllerDelegate

- (void)threadWasSelected:(TSThread *)thread
{
    OWSAssert(self.attachment);
    OWSAssert(thread);

    __weak typeof(self) weakSelf = self;

    BOOL didShowSNAlert =
        [SafetyNumberConfirmationAlert presentAlertIfNecessaryWithRecipientIds:thread.recipientIdentifiers
                                                              confirmationText:[SafetyNumberStrings confirmSendButton]
                                                               contactsManager:self.contactsManager
                                                                    completion:^(BOOL didConfirm) {
                                                                        if (didConfirm) {
                                                                            [weakSelf threadWasSelected:thread];
                                                                        }
                                                                    }];
    if (didShowSNAlert) {
        return;
    }

    [ThreadUtil sendMessageWithAttachment:self.attachment inThread:thread messageSender:self.messageSender];

    [Environment messageThreadId:thread.uniqueId];
}

- (BOOL)canSelectBlockedContact
{
    return NO;
}

- (nullable UIView *)createHeaderWithSearchBar:(UISearchBar *)searchBar
{
    OWSAssert(searchBar)

        const CGFloat imageSize
        = ScaleFromIPhone5To7Plus(40, 50);
    const CGFloat imageLabelSpacing = ScaleFromIPhone5To7Plus(5, 8);
    const CGFloat titleVSpacing = ScaleFromIPhone5To7Plus(10, 15);
    const CGFloat contentVMargin = 20;

    UIView *header = [UIView new];
    header.backgroundColor = [UIColor whiteColor];

    UIView *titleLabel = [self createTitleLabel];
    [titleLabel sizeToFit];
    [header addSubview:titleLabel];
    [titleLabel autoHCenterInSuperview];
    [titleLabel autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:contentVMargin];

    UIView *fileView = [UIView new];
    [header addSubview:fileView];
    [fileView autoHCenterInSuperview];
    [fileView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:titleLabel withOffset:titleVSpacing];

    UIImage *image = [UIImage imageNamed:@"file-thin-black-filled-large"];
    OWSAssert(image);
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.layer.minificationFilter = kCAFilterTrilinear;
    imageView.layer.magnificationFilter = kCAFilterTrilinear;
    imageView.layer.shadowColor = [UIColor blackColor].CGColor;
    imageView.layer.shadowRadius = 2.f;
    imageView.layer.shadowOpacity = 0.2f;
    imageView.layer.shadowOffset = CGSizeMake(0.75f, 0.75f);
    [fileView addSubview:imageView];
    [imageView autoSetDimension:ALDimensionWidth toSize:imageSize];
    [imageView autoSetDimension:ALDimensionHeight toSize:imageSize];
    [imageView autoPinLeadingToSuperView];
    [imageView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [imageView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    UIView *fileNameLabel = [self createFileNameLabel];
    [fileView addSubview:fileNameLabel];
    [fileNameLabel autoAlignAxis:ALAxisHorizontal toSameAxisOfView:imageView];
    [fileNameLabel autoPinLeadingToTrailingOfView:imageView margin:imageLabelSpacing];
    [fileNameLabel autoPinTrailingToSuperView];

    [header addSubview:searchBar];
    [searchBar autoPinWidthToSuperview];
    [searchBar autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:fileView withOffset:contentVMargin];
    [searchBar autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    // UITableViewController.tableHeaderView must have its height set.
    header.frame = CGRectMake(0,
        0,
        0,
        (contentVMargin * 2 + titleLabel.frame.size.height + titleVSpacing + imageSize + searchBar.frame.size.height));

    return header;
}

- (NSString *)formattedFileName
{
    // AppDelegate already verifies that this attachment has a valid filename.
    //
    // TODO: If we reuse this VC, for example to offer a "forward attachment to other thread",
    //       feature, this assumption would no longer apply.
    OWSAssert(self.attachment) NSString *filename =
        [self.attachment.filename stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    OWSAssert(filename.length > 0);
    const NSUInteger kMaxFilenameLength = 20;
    if (filename.length > kMaxFilenameLength) {
        // Truncate the filename if necessary.
        //
        // TODO: Use l10n-safe truncation.
        filename = [[[filename substringToIndex:kMaxFilenameLength / 2] stringByAppendingString:@"…"]
            stringByAppendingString:[filename substringFromIndex:filename.length - kMaxFilenameLength / 2]];
    }
    return filename;
}

- (UIView *)createFileNameLabel
{
    UILabel *label = [UILabel new];
    label.text = [self formattedFileName];
    label.textColor = [UIColor ows_materialBlueColor];
    label.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(16.f, 20.f)];
    return label;
}


- (UIView *)createTitleLabel
{
    UILabel *label = [UILabel new];
    label.text
        = NSLocalizedString(@"SEND_EXTERNAL_FILE_HEADER_TITLE", @"Header title for the 'send external file' view.");
    label.textColor = [UIColor blackColor];
    label.font = [UIFont ows_mediumFontWithSize:ScaleFromIPhone5To7Plus(18.f, 20.f)];
    return label;
}

@end

NS_ASSUME_NONNULL_END
