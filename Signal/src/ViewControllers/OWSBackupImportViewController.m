//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupImportViewController.h"
#import "OWSBackup.h"
#import "OWSProgressView.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <SignalMessaging/AttachmentSharing.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalServiceKit/MIMETypeUtil.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSBackupImportViewController () <OWSBackupDelegate>

@property (nonatomic) OWSBackup *backup;

@property (nonatomic, nullable) OWSProgressView *progressView;

@end

#pragma mark -

@implementation OWSBackupImportViewController

- (void)loadView
{
    [super loadView];

    self.view.backgroundColor = [UIColor whiteColor];

    self.navigationItem.title = NSLocalizedString(@"BACKUP_IMPORT_VIEW_TITLE", @"Title for the 'backup import' view.");
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(dismissWasPressed:)];

    self.backup.delegate = self;

    [self updateUI];
}

- (void)importBackup:(NSString *)backupZipPath password:(NSString *_Nullable)password
{
    OWSAssertIsOnMainThread();
    OWSAssert(backupZipPath.length > 0);

    // We set ourselves as the delegate of the backup later,
    // after we've loaded our view.
    self.backup = [OWSBackup new];
    [self.backup importBackup:backupZipPath password:password];
}

- (void)updateUI
{
    for (UIView *subview in self.view.subviews) {
        [subview removeFromSuperview];
    }
    self.progressView = nil;

    switch (self.backup.backupState) {
        case OWSBackupState_InProgress:
            [self showInProgressUI];
            break;
        case OWSBackupState_Cancelled:
            [self showCancelledUI];
            break;
        case OWSBackupState_Complete:
            [self showCompleteUI];
            break;
        case OWSBackupState_Failed:
            [self showFailedUI];
            break;
    }
}

- (void)showInProgressUI
{
    self.progressView = [OWSProgressView new];
    self.progressView.color = [UIColor ows_materialBlueColor];
    self.progressView.progress = self.backup.backupProgress;
    [self.progressView autoSetDimension:ALDimensionWidth toSize:300];
    [self.progressView autoSetDimension:ALDimensionHeight toSize:20];

    UILabel *label = [UILabel new];
    label.text = NSLocalizedString(
        @"BACKUP_IMPORT_IN_PROGRESS_MESSAGE", @"Message indicating that backup import is in progress.");
    label.textColor = [UIColor blackColor];
    label.font = [UIFont ows_regularFontWithSize:18.f];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;

    UIView *container = [UIView verticalStackWithSubviews:@[
        label,
        self.progressView,
    ]
                                                  spacing:10];
    [self.view addSubview:container];
    [container autoVCenterInSuperview];
    [container autoPinWidthToSuperviewWithMargin:25.f];
}

- (void)showCancelledUI
{
    // Show nothing.
}

- (void)showCompleteUI
{
    NSMutableArray<UIView *> *subviews = [NSMutableArray new];

    {
        NSString *message = NSLocalizedString(
            @"BACKUP_IMPORT_COMPLETE_MESSAGE", @"Message indicating that backup import is complete.");

        UILabel *label = [UILabel new];
        label.text = message;
        label.textColor = [UIColor blackColor];
        label.font = [UIFont ows_regularFontWithSize:18.f];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        [subviews addObject:label];
    }

    [subviews addObject:[UIView new]];

    [subviews addObject:[self makeButtonWithTitle:NSLocalizedString(@"BACKUP_IMPORT_RESTART_BUTTON",
                                                      @"Label for button that restarts app to complete restore.")
                                         selector:@selector(restartApp)]];

    UIView *container = [UIView verticalStackWithSubviews:subviews spacing:10];
    [self.view addSubview:container];
    [container autoVCenterInSuperview];
    [container autoPinWidthToSuperviewWithMargin:25.f];
}

- (void)showFailedUI
{
    NSMutableArray<UIView *> *subviews = [NSMutableArray new];

    {
        NSString *message
            = NSLocalizedString(@"BACKUP_IMPORT_FAILED_MESSAGE", @"Message indicating that backup import failed.");

        UILabel *label = [UILabel new];
        label.text = message;
        label.textColor = [UIColor blackColor];
        label.font = [UIFont ows_regularFontWithSize:18.f];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        [subviews addObject:label];
    }

    // TODO: We should offer the option to save the backup to "Files", iCloud, Dropbox, etc.

    UIView *container = [UIView verticalStackWithSubviews:subviews spacing:10];
    [self.view addSubview:container];
    [container autoVCenterInSuperview];
    [container autoPinWidthToSuperviewWithMargin:25.f];
}

- (UIView *)makeButtonWithTitle:(NSString *)title selector:(SEL)selector
{
    const CGFloat kButtonHeight = 40;
    OWSFlatButton *button = [OWSFlatButton buttonWithTitle:title
                                                      font:[OWSFlatButton fontForHeight:kButtonHeight]
                                                titleColor:[UIColor whiteColor]
                                           backgroundColor:[UIColor ows_materialBlueColor]
                                                    target:self
                                                  selector:selector];
    [button autoSetDimension:ALDimensionWidth toSize:140];
    [button autoSetDimension:ALDimensionHeight toSize:kButtonHeight];
    return button;
}

- (void)dismissWasPressed:(id)sender
{
    [self.backup cancel];

    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)restartApp
{
    DDLogInfo(@"%@ %s.", self.logTag, __PRETTY_FUNCTION__);

    OWSRaiseException(@"OWSBackup_RestartAppToCompleteBackupRestore", @"Killing app to complete backup restore");
}

#pragma mark - OWSBackupDelegate

- (void)backupStateDidChange
{
    DDLogInfo(@"%@ %s.", self.logTag, __PRETTY_FUNCTION__);

    [self updateUI];
}

- (void)backupProgressDidChange
{
    DDLogInfo(@"%@ %s.", self.logTag, __PRETTY_FUNCTION__);

    self.progressView.progress = self.backup.backupProgress;
}

@end

NS_ASSUME_NONNULL_END
