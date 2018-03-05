//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupSettingsViewController.h"
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

@interface OWSBackupSettingsViewController ()
//<OWSBackupDelegate>

//@property (nonatomic) OWSBackup *backup;
//
//@property (nonatomic, nullable) OWSProgressView *progressView;

@end

#pragma mark -

@implementation OWSBackupSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"SETTINGS_BACKUP", @"Label for the backup view in app settings.");

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(backupStateDidChange:)
                                                 name:NSNotificationNameBackupStateDidChange
                                               object:nil];

    [self updateTableContents];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    BOOL isBackupEnabled = [OWSBackup.sharedManager isBackupEnabled];

    // TODO: This UI is temporary.
    // Enabling backup will involve entering and registering a PIN.
    OWSTableSection *enableSection = [OWSTableSection new];
    enableSection.headerTitle = NSLocalizedString(@"SETTINGS_BACKUP", @"Label for the backup view in app settings.");
    [enableSection
        addItem:[OWSTableItem switchItemWithText:
                                  NSLocalizedString(@"SETTINGS_BACKUP_ENABLING_SWITCH",
                                      @"Label for switch in settings that controls whether or not backup is enabled.")
                                            isOn:isBackupEnabled
                                          target:self
                                        selector:@selector(isBackupEnabledDidChange:)]];
    [contents addSection:enableSection];

    self.contents = contents;
}

- (void)isBackupEnabledDidChange:(UISwitch *)sender
{
    [OWSBackup.sharedManager setIsBackupEnabled:sender.isOn];
}

#pragma mark - Events

- (void)backupStateDidChange:(NSNotification *)notification
{
    [self updateTableContents];
}

//- (void)loadView
//{
//    [super loadView];
//
//    self.view.backgroundColor = [UIColor whiteColor];
//
//    self.navigationItem.title = NSLocalizedString(@"BACKUP_EXPORT_VIEW_TITLE", @"Title for the 'backup export'
//    view."); self.navigationItem.leftBarButtonItem =
//        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
//                                                      target:self
//                                                      action:@selector(dismissWasPressed:)];
//
//    self.backup.delegate = self;
//
//    [self updateUI];
//}
//
//- (void)exportBackup:(TSThread *_Nullable)currentThread skipPassword:(BOOL)skipPassword
//{
//    OWSAssertIsOnMainThread();
//
//    // We set ourselves as the delegate of the backup later,
//    // after we've loaded our view.
//    self.backup = [OWSBackup new];
//    [self.backup exportBackup:currentThread skipPassword:skipPassword];
//}
//
//- (void)updateUI
//{
//    for (UIView *subview in self.view.subviews) {
//        [subview removeFromSuperview];
//    }
//    self.progressView = nil;
//
//    switch (self.backup.backupState) {
//        case OWSBackupState_InProgress:
//            [self showInProgressUI];
//            break;
//        case OWSBackupState_Cancelled:
//            [self showCancelledUI];
//            break;
//        case OWSBackupState_Complete:
//            [self showCompleteUI];
//            break;
//        case OWSBackupState_Failed:
//            [self showFailedUI];
//            break;
//    }
//}
//
//- (void)showInProgressUI
//{
//    self.progressView = [OWSProgressView new];
//    self.progressView.color = [UIColor ows_materialBlueColor];
//    self.progressView.progress = self.backup.backupProgress;
//    [self.progressView autoSetDimension:ALDimensionWidth toSize:300];
//    [self.progressView autoSetDimension:ALDimensionHeight toSize:20];
//
//    UILabel *label = [UILabel new];
//    label.text = NSLocalizedString(
//        @"BACKUP_EXPORT_IN_PROGRESS_MESSAGE", @"Message indicating that backup export is in progress.");
//    label.textColor = [UIColor blackColor];
//    label.font = [UIFont ows_regularFontWithSize:18.f];
//    label.textAlignment = NSTextAlignmentCenter;
//    label.numberOfLines = 0;
//    label.lineBreakMode = NSLineBreakByWordWrapping;
//
//    UIView *container = [UIView verticalStackWithSubviews:@[
//        label,
//        self.progressView,
//    ]
//                                                  spacing:10];
//    [self.view addSubview:container];
//    [container autoVCenterInSuperview];
//    [container autoPinWidthToSuperviewWithMargin:25.f];
//}
//
//- (void)showCancelledUI
//{
//    // Show nothing.
//}
//
//- (void)showCompleteUI
//{
//    NSMutableArray<UIView *> *subviews = [NSMutableArray new];
//
//    {
//        NSString *message = NSLocalizedString(
//            @"BACKUP_EXPORT_COMPLETE_MESSAGE", @"Message indicating that backup export is complete.");
//
//        UILabel *label = [UILabel new];
//        label.text = message;
//        label.textColor = [UIColor blackColor];
//        label.font = [UIFont ows_regularFontWithSize:18.f];
//        label.textAlignment = NSTextAlignmentCenter;
//        label.numberOfLines = 0;
//        label.lineBreakMode = NSLineBreakByWordWrapping;
//        [subviews addObject:label];
//    }
//
//    if (self.backup.backupPassword) {
//        NSString *message = [NSString stringWithFormat:NSLocalizedString(@"BACKUP_EXPORT_PASSWORD_MESSAGE_FORMAT",
//                                                           @"Format for message indicating that backup export "
//                                                           @"is complete. Embeds: {{the backup password}}."),
//                                      self.backup.backupPassword];
//
//        UILabel *label = [UILabel new];
//        label.text = message;
//        label.textColor = [UIColor blackColor];
//        label.font = [UIFont ows_regularFontWithSize:14.f];
//        label.textAlignment = NSTextAlignmentCenter;
//        label.numberOfLines = 0;
//        label.lineBreakMode = NSLineBreakByWordWrapping;
//        [subviews addObject:label];
//    }
//
//    [subviews addObject:[UIView new]];
//
//    if (self.backup.backupPassword) {
//        [subviews
//            addObject:[self makeButtonWithTitle:NSLocalizedString(@"BACKUP_EXPORT_COPY_PASSWORD_BUTTON",
//                                                    @"Label for button that copies backup password to the
//                                                    pasteboard.")
//                                       selector:@selector(copyPassword)]];
//    }
//
//    [subviews addObject:[self makeButtonWithTitle:NSLocalizedString(@"BACKUP_EXPORT_SHARE_BACKUP_BUTTON",
//                                                      @"Label for button that opens share UI for backup.")
//                                         selector:@selector(shareBackup)]];
//
//    if (self.backup.currentThread) {
//        [subviews
//            addObject:[self makeButtonWithTitle:NSLocalizedString(@"BACKUP_EXPORT_SEND_BACKUP_BUTTON",
//                                                    @"Label for button that 'send backup' in the current
//                                                    conversation.")
//                                       selector:@selector(sendBackup)]];
//    }
//
//    // TODO: We should offer the option to save the backup to "Files", iCloud, Dropbox, etc.
//
//    UIView *container = [UIView verticalStackWithSubviews:subviews spacing:10];
//    [self.view addSubview:container];
//    [container autoVCenterInSuperview];
//    [container autoPinWidthToSuperviewWithMargin:25.f];
//}
//
//- (void)showFailedUI
//{
//    NSMutableArray<UIView *> *subviews = [NSMutableArray new];
//
//    {
//        NSString *message
//            = NSLocalizedString(@"BACKUP_EXPORT_FAILED_MESSAGE", @"Message indicating that backup export failed.");
//
//        UILabel *label = [UILabel new];
//        label.text = message;
//        label.textColor = [UIColor blackColor];
//        label.font = [UIFont ows_regularFontWithSize:18.f];
//        label.textAlignment = NSTextAlignmentCenter;
//        label.numberOfLines = 0;
//        label.lineBreakMode = NSLineBreakByWordWrapping;
//        [subviews addObject:label];
//    }
//
//    // TODO: We should offer the option to save the backup to "Files", iCloud, Dropbox, etc.
//
//    UIView *container = [UIView verticalStackWithSubviews:subviews spacing:10];
//    [self.view addSubview:container];
//    [container autoVCenterInSuperview];
//    [container autoPinWidthToSuperviewWithMargin:25.f];
//}
//
//- (UIView *)makeButtonWithTitle:(NSString *)title selector:(SEL)selector
//{
//    const CGFloat kButtonHeight = 40;
//    OWSFlatButton *button = [OWSFlatButton buttonWithTitle:title
//                                                      font:[OWSFlatButton fontForHeight:kButtonHeight]
//                                                titleColor:[UIColor whiteColor]
//                                           backgroundColor:[UIColor ows_materialBlueColor]
//                                                    target:self
//                                                  selector:selector];
//    [button autoSetDimension:ALDimensionWidth toSize:140];
//    [button autoSetDimension:ALDimensionHeight toSize:kButtonHeight];
//    return button;
//}
//
//- (void)copyPassword
//{
//    OWSAssert(self.backup.backupPassword.length > 0);
//
//    // TODO: We could consider clearing the password from the pasteboard after a certain delay.
//    [UIPasteboard.generalPasteboard setString:self.backup.backupPassword];
//}
//
//- (void)shareBackup
//{
//    OWSAssertIsOnMainThread();
//    OWSAssert(self.backup.backupZipPath.length > 0);
//
//    [AttachmentSharing showShareUIForURL:[NSURL fileURLWithPath:self.backup.backupZipPath]];
//}
//
//- (void)sendBackup
//{
//    OWSAssertIsOnMainThread();
//    OWSAssert(self.backup.backupZipPath.length > 0);
//    OWSAssert(self.backup.currentThread);
//
//    [ModalActivityIndicatorViewController
//        presentFromViewController:self
//                        canCancel:NO
//                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
//                      NSString *fileName = [self.backup.backupZipPath lastPathComponent];
//
//                      OWSMessageSender *messageSender = [Environment current].messageSender;
//                      NSString *utiType = [MIMETypeUtil utiTypeForFileExtension:fileName.pathExtension];
//                      DataSource *_Nullable dataSource =
//                          [DataSourcePath dataSourceWithFilePath:self.backup.backupZipPath];
//                      [dataSource setSourceFilename:fileName];
//                      SignalAttachment *attachment =
//                          [SignalAttachment attachmentWithDataSource:dataSource dataUTI:utiType];
//                      if (!attachment || [attachment hasError]) {
//                          OWSFail(@"%@ attachment[%@]: %@",
//                              self.logTag,
//                              [attachment sourceFilename],
//                              [attachment errorName]);
//                          return;
//                      }
//                      dispatch_async(dispatch_get_main_queue(), ^{
//                          [ThreadUtil
//                              sendMessageWithAttachment:attachment
//                                               inThread:self.backup.currentThread
//                                          messageSender:messageSender
//                                             completion:^(NSError *_Nullable error) {
//
//                                                 OWSAssertIsOnMainThread();
//                                                 [modalActivityIndicator dismissWithCompletion:^{
//                                                     if (error) {
//                                                         DDLogError(@"%@ send backup failed: %@", self.logTag, error);
//                                                         [OWSAlerts
//                                                             showAlertWithTitle:NSLocalizedString(
//                                                                                    @"BACKUP_EXPORT_SEND_BACKUP_FAILED",
//                                                                                    @"Message indicating that sending
//                                                                                    "
//                                                                                    @"the backup failed.")];
//                                                     } else {
//                                                         [OWSAlerts
//                                                             showAlertWithTitle:
//                                                                 NSLocalizedString(@"BACKUP_EXPORT_SEND_BACKUP_SUCCESS",
//                                                                     @"Message indicating that sending the backup "
//                                                                     @"succeeded.")];
//                                                     }
//                                                 }];
//                                             }];
//                      });
//                  }];
//}
//
//- (void)dismissWasPressed:(id)sender
//{
//    [self.backup cancel];
//
//    [self.navigationController popViewControllerAnimated:YES];
//}
//
//#pragma mark - OWSBackupDelegate
//
//- (void)backupStateDidChange
//{
//    DDLogInfo(@"%@ %s.", self.logTag, __PRETTY_FUNCTION__);
//
//    [self updateUI];
//}
//
//- (void)backupProgressDidChange
//{
//    DDLogInfo(@"%@ %s.", self.logTag, __PRETTY_FUNCTION__);
//
//    self.progressView.progress = self.backup.backupProgress;
//}

@end

NS_ASSUME_NONNULL_END
