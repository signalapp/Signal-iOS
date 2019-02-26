//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupSettingsViewController.h"
#import "OWSBackup.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalMessaging/AttachmentSharing.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalServiceKit/MIMETypeUtil.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSBackupSettingsViewController ()

@property (nonatomic, nullable) NSError *iCloudError;

@end

#pragma mark -

@implementation OWSBackupSettingsViewController

#pragma mark - Dependencies

- (OWSBackup *)backup
{
    OWSAssertDebug(AppEnvironment.shared.backup);

    return AppEnvironment.shared.backup;
}

#pragma mark -

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"SETTINGS_BACKUP", @"Label for the backup view in app settings.");

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(backupStateDidChange:)
                                                 name:NSNotificationNameBackupStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];

    [self updateTableContents];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self updateTableContents];
    [self updateICloudStatus];
}

- (void)updateICloudStatus
{
    __weak OWSBackupSettingsViewController *weakSelf = self;
    [[self.backup ensureCloudKitAccess]
            .then(^{
                OWSAssertIsOnMainThread();

                weakSelf.iCloudError = nil;
                [weakSelf updateTableContents];
            })
            .catch(^(NSError *error) {
                OWSAssertIsOnMainThread();

                weakSelf.iCloudError = error;
                [weakSelf updateTableContents];
            }) retainUntilComplete];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    BOOL isBackupEnabled = [OWSBackup.sharedManager isBackupEnabled];

    if (self.iCloudError) {
        OWSTableSection *iCloudSection = [OWSTableSection new];
        iCloudSection.headerTitle = NSLocalizedString(
            @"SETTINGS_BACKUP_ICLOUD_STATUS", @"Label for iCloud status row in the in the backup settings view.");
        [iCloudSection
            addItem:[OWSTableItem
                        longDisclosureItemWithText:[OWSBackupAPI errorMessageForCloudKitAccessError:self.iCloudError]
                                       actionBlock:^{
                                           [[UIApplication sharedApplication]
                                               openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
                                       }]];
        [contents addSection:iCloudSection];
    }

    // TODO: This UI is temporary.
    // Enabling backup will involve entering and registering a PIN.
    OWSTableSection *enableSection = [OWSTableSection new];
    enableSection.headerTitle = NSLocalizedString(@"SETTINGS_BACKUP", @"Label for the backup view in app settings.");
    [enableSection
        addItem:[OWSTableItem switchItemWithText:
                                  NSLocalizedString(@"SETTINGS_BACKUP_ENABLING_SWITCH",
                                      @"Label for switch in settings that controls whether or not backup is enabled.")
                                       isOnBlock:^{
                                           return [OWSBackup.sharedManager isBackupEnabled];
                                       }
                                          target:self
                                        selector:@selector(isBackupEnabledDidChange:)]];
    [contents addSection:enableSection];

    if (isBackupEnabled) {
        // TODO: This UI is temporary.
        // Enabling backup will involve entering and registering a PIN.
        OWSTableSection *progressSection = [OWSTableSection new];
        [progressSection
            addItem:[OWSTableItem
                        labelItemWithText:NSLocalizedString(@"SETTINGS_BACKUP_STATUS",
                                              @"Label for backup status row in the in the backup settings view.")
                            accessoryText:NSStringForBackupExportState(OWSBackup.sharedManager.backupExportState)]];
        if (OWSBackup.sharedManager.backupExportState == OWSBackupState_InProgress) {
            if (OWSBackup.sharedManager.backupExportDescription) {
                [progressSection
                    addItem:[OWSTableItem
                                labelItemWithText:NSLocalizedString(@"SETTINGS_BACKUP_PHASE",
                                                      @"Label for phase row in the in the backup settings view.")
                                    accessoryText:OWSBackup.sharedManager.backupExportDescription]];
                if (OWSBackup.sharedManager.backupExportProgress) {
                    NSUInteger progressPercent
                        = (NSUInteger)round(OWSBackup.sharedManager.backupExportProgress.floatValue * 100);
                    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
                    [numberFormatter setNumberStyle:NSNumberFormatterPercentStyle];
                    [numberFormatter setMaximumFractionDigits:0];
                    [numberFormatter setMultiplier:@1];
                    NSString *progressString = [numberFormatter stringFromNumber:@(progressPercent)];
                    [progressSection
                        addItem:[OWSTableItem
                                    labelItemWithText:NSLocalizedString(@"SETTINGS_BACKUP_PROGRESS",
                                                          @"Label for phase row in the in the backup settings view.")
                                        accessoryText:progressString]];
                }
            }
        }

        switch (OWSBackup.sharedManager.backupExportState) {
            case OWSBackupState_Idle:
            case OWSBackupState_Failed:
            case OWSBackupState_Succeeded:
                [progressSection
                    addItem:[OWSTableItem disclosureItemWithText:
                                              NSLocalizedString(@"SETTINGS_BACKUP_BACKUP_NOW",
                                                  @"Label for 'backup now' button in the backup settings view.")
                                                     actionBlock:^{
                                                         [OWSBackup.sharedManager tryToExportBackup];
                                                     }]];
                break;
            case OWSBackupState_InProgress:
                [progressSection
                    addItem:[OWSTableItem disclosureItemWithText:
                                              NSLocalizedString(@"SETTINGS_BACKUP_CANCEL_BACKUP",
                                                  @"Label for 'cancel backup' button in the backup settings view.")
                                                     actionBlock:^{
                                                         [OWSBackup.sharedManager cancelExportBackup];
                                                     }]];
                break;
        }

        [contents addSection:progressSection];
    }

    self.contents = contents;
}

- (void)isBackupEnabledDidChange:(UISwitch *)sender
{
    [OWSBackup.sharedManager setIsBackupEnabled:sender.isOn];

    [self updateTableContents];
}

#pragma mark - Events

- (void)backupStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateTableContents];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateICloudStatus];
}

@end

NS_ASSUME_NONNULL_END
