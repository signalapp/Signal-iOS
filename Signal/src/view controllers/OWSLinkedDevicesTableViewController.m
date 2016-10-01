//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSLinkedDevicesTableViewController.h"
#import "OWSDeviceTableViewCell.h"
#import "OWSLinkDeviceViewController.h"
#import <SignalServiceKit/OWSDevice.h>
#import <SignalServiceKit/OWSDevicesService.h>
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import <YapDatabase/YapDatabaseViewConnection.h>
#import <YapDatabase/YapDatabaseViewMappings.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSLinkedDevicesTableViewController ()

@property YapDatabaseConnection *dbConnection;
@property YapDatabaseViewMappings *deviceMappings;
@property NSTimer *pollingRefreshTimer;
@property BOOL isExpectingMoreDevices;

@end

int const OWSLinkedDevicesTableViewControllerSectionExistingDevices = 0;
int const OWSLinkedDevicesTableViewControllerSectionAddDevice = 1;

@implementation OWSLinkedDevicesTableViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = NSLocalizedString(@"LINKED_DEVICES_TITLE", @"Menu item and navbar title for the device manager");

    self.isExpectingMoreDevices = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 70;

    self.dbConnection = [[TSStorageManager sharedManager] newDatabaseConnection];
    [self.dbConnection beginLongLivedReadTransaction];
    self.deviceMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[ TSSecondaryDevicesGroup ]
                                                                     view:TSSecondaryDevicesDatabaseViewExtensionName];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.deviceMappings updateWithTransaction:transaction];
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:self.dbConnection.database];


    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(refreshDevices) forControlEvents:UIControlEventValueChanged];

    [self setupEditButton];
    // So we can still tap on "add new device"
    self.tableView.allowsSelectionDuringEditing = YES;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshDevices];
    // HACK to unselect rows when swiping back
    // http://stackoverflow.com/questions/19379510/uitableviewcell-doesnt-get-deselected-when-swiping-back-quickly
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.pollingRefreshTimer invalidate];
}

// Don't show edit button for an empty table
- (void)setupEditButton
{
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        if ([OWSDevice hasSecondaryDevicesWithTransaction:transaction]) {
            self.navigationItem.rightBarButtonItem = self.editButtonItem;
        } else {
            self.navigationItem.rightBarButtonItem = nil;
        }
    }];
}

- (void)expectMoreDevices
{
    self.isExpectingMoreDevices = YES;

    // When you delete and re-add a device, you will be returned to this view in editing mode, making your newly
    // added device appear with a delete icon. Probably not what you want.
    self.editing = NO;

    __weak typeof(self) wself = self;
    self.pollingRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:(10.0)
                                                                target:wself
                                                              selector:@selector(refreshDevices)
                                                              userInfo:nil
                                                               repeats:YES];

    NSString *progressText = NSLocalizedString(@"WAITING_TO_COMPLETE_DEVICE_LINK_TEXT",
        @"Activity indicator title, shown upon returning to the device "
        @"manager, until you complete the provisioning process on desktop");
    NSAttributedString *progressTitle = [[NSAttributedString alloc] initWithString:progressText];

    // HACK to get refreshControl title to align properly.
    self.refreshControl.attributedTitle = progressTitle;
    [self.refreshControl endRefreshing];

    dispatch_async(dispatch_get_main_queue(), ^{
        self.refreshControl.attributedTitle = progressTitle;
        [self.refreshControl beginRefreshing];
        // Needed to show refresh control programatically
        [self.tableView setContentOffset:CGPointMake(0, -self.refreshControl.frame.size.height) animated:NO];
    });
    // END HACK to get refreshControl title to align properly.
}

- (void)refreshDevices
{
    __weak typeof(self) wself = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[OWSDevicesService new] getDevicesWithSuccess:^(NSArray<OWSDevice *> *devices) {
            if (devices.count > [OWSDevice numberOfKeysInCollection]) {
                // Got our new device, we can stop refreshing.
                wself.isExpectingMoreDevices = NO;
                [wself.pollingRefreshTimer invalidate];
                dispatch_async(dispatch_get_main_queue(), ^{
                    wself.refreshControl.attributedTitle = nil;
                });
            }
            [OWSDevice replaceAll:devices];

            if (!self.isExpectingMoreDevices) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [wself.refreshControl endRefreshing];
                });
            }
        }
            failure:^(NSError *error) {
                DDLogError(@"Failed to fetch devices in linkedDevices controller with error: %@", error);

                NSString *alertTitle = NSLocalizedString(
                    @"DEVICE_LIST_UPDATE_FAILED_TITLE", @"Alert title that can occur when viewing device manager.");

                UIAlertController *alertController =
                    [UIAlertController alertControllerWithTitle:alertTitle
                                                        message:error.localizedDescription
                                                 preferredStyle:UIAlertControllerStyleAlert];

                NSString *retryTitle = NSLocalizedString(
                    @"RETRY_BUTTON_TEXT", @"Generic text for button that retries whatever the last action was.");
                UIAlertAction *retryAction = [UIAlertAction actionWithTitle:retryTitle
                                                                      style:UIAlertActionStyleDefault
                                                                    handler:^(UIAlertAction *action) {
                                                                        [wself refreshDevices];
                                                                    }];
                [alertController addAction:retryAction];

                NSString *dismissTitle
                    = NSLocalizedString(@"DISMISS_BUTTON_TEXT", @"Generic short text for button to dismiss a dialog");
                UIAlertAction *dismissAction =
                    [UIAlertAction actionWithTitle:dismissTitle style:UIAlertActionStyleCancel handler:nil];
                [alertController addAction:dismissAction];

                dispatch_async(dispatch_get_main_queue(), ^{
                    [wself.refreshControl endRefreshing];
                    [wself presentViewController:alertController animated:YES completion:nil];
                });
            }];
    });
}

#pragma mark - Table view data source

- (void)yapDatabaseModified:(NSNotification *)notification
{
    NSArray *notifications = [self.dbConnection beginLongLivedReadTransaction];
    [self setupEditButton];

    if ([notifications count] == 0) {
        return; // already processed commit
    }

    NSArray *rowChanges;
    [[self.dbConnection ext:TSSecondaryDevicesDatabaseViewExtensionName] getSectionChanges:nil
                                                                                rowChanges:&rowChanges
                                                                          forNotifications:notifications
                                                                              withMappings:self.deviceMappings];
    if (rowChanges.count == 0) {
        // There aren't any changes that affect our tableView!
        return;
    }

    [self.tableView beginUpdates];

    for (YapDatabaseViewRowChange *rowChange in rowChanges) {
        switch (rowChange.type) {
            case YapDatabaseViewChangeDelete: {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeInsert: {
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeMove: {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeUpdate: {
                [self.tableView reloadRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationNone];
                break;
            }
        }
    }

    [self.tableView endUpdates];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case OWSLinkedDevicesTableViewControllerSectionExistingDevices:
            return (NSInteger)[self.deviceMappings numberOfItemsInSection:(NSUInteger)section];
        case OWSLinkedDevicesTableViewControllerSectionAddDevice:
            return 1;

        default:
            DDLogError(@"Unknown section: %ld", (long)section);
            return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == OWSLinkedDevicesTableViewControllerSectionAddDevice) {
        UITableViewCell *addNewDeviceCell =
            [tableView dequeueReusableCellWithIdentifier:@"AddNewDevice" forIndexPath:indexPath];
        addNewDeviceCell.textLabel.text
            = NSLocalizedString(@"LINK_NEW_DEVICE_TITLE", @"Navigation title when scanning QR code to add new device.");
        addNewDeviceCell.detailTextLabel.text
            = NSLocalizedString(@"LINK_NEW_DEVICE_SUBTITLE", @"Subheading for 'Link New Device' navigation");
        return addNewDeviceCell;
    } else if (indexPath.section == OWSLinkedDevicesTableViewControllerSectionExistingDevices) {
        OWSDeviceTableViewCell *cell =
            [tableView dequeueReusableCellWithIdentifier:@"ExistingDevice" forIndexPath:indexPath];
        OWSDevice *device = [self deviceForRowAtIndexPath:indexPath];
        [cell configureWithDevice:device];
        return cell;
    } else {
        DDLogError(@"Unknown section: %@", indexPath);
        return nil;
    }
}

- (nullable OWSDevice *)deviceForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == OWSLinkedDevicesTableViewControllerSectionExistingDevices) {
        __block OWSDevice *device;
        [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            device = [[transaction extension:TSSecondaryDevicesDatabaseViewExtensionName]
                objectAtIndexPath:indexPath
                     withMappings:self.deviceMappings];
        }];

        return device;
    }

    return nil;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return indexPath.section == OWSLinkedDevicesTableViewControllerSectionExistingDevices;
}

- (nullable NSString *)tableView:(UITableView *)tableView
    titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NSLocalizedString(@"UNLINK_ACTION", "button title for unlinking a device");
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        OWSDevice *device = [self deviceForRowAtIndexPath:indexPath];
        [self touchedUnlinkControlForDevice:device
                                    success:^{
                                        DDLogInfo(@"Removing unlinked device with deviceId: %ld", (long)device.deviceId);
                                        [device remove];
                                    }];
    }
}

- (void)touchedUnlinkControlForDevice:(OWSDevice *)device success:(void (^)())successCallback
{
    NSString *confirmationTitleFormat
        = NSLocalizedString(@"UNLINK_CONFIRMATION_ALERT_TITLE", @"Alert title for confirming device deletion");
    NSString *confirmationTitle = [NSString stringWithFormat:confirmationTitleFormat, device.name];
    NSString *confirmationMessage
        = NSLocalizedString(@"UNLINK_CONFIRMATION_ALERT_BODY", @"Alert message to confirm unlinking a device");
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:confirmationTitle
                                                                             message:confirmationMessage
                                                                      preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alertController addAction:cancelAction];

    UIAlertAction *unlinkAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"UNLINK_ACTION", "button title for unlinking a device")
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *action) {
                                   dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                                       [self unlinkDevice:device success:successCallback];
                                   });
                               }];
    [alertController addAction:unlinkAction];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alertController animated:YES completion:nil];
    });
}

- (void)unlinkDevice:(OWSDevice *)device success:(void (^)())successCallback
{
    [[OWSDevicesService new] unlinkDevice:device
                                  success:successCallback
                                  failure:^(NSError *error) {
                                      NSString *title = NSLocalizedString(
                                          @"UNLINKING_FAILED_ALERT_TITLE", @"Alert title when unlinking device fails");
                                      UIAlertController *alertController =
                                          [UIAlertController alertControllerWithTitle:title
                                                                              message:error.localizedDescription
                                                                       preferredStyle:UIAlertControllerStyleAlert];

                                      UIAlertAction *retryAction =
                                          [UIAlertAction actionWithTitle:NSLocalizedString(@"RETRY_BUTTON_TEXT", nil)
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *aaction) {
                                                                     [self unlinkDevice:device success:successCallback];
                                                                 }];
                                      [alertController addAction:retryAction];

                                      UIAlertAction *cancelRetryAction =
                                          [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                                                                   style:UIAlertActionStyleCancel
                                                                 handler:nil];
                                      [alertController addAction:cancelRetryAction];

                                      dispatch_async(dispatch_get_main_queue(), ^{
                                          [self presentViewController:alertController animated:YES completion:nil];
                                      });
                                  }];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(nullable id)sender
{
    if ([segue.destinationViewController isKindOfClass:[OWSLinkDeviceViewController class]]) {
        OWSLinkDeviceViewController *controller = (OWSLinkDeviceViewController *)segue.destinationViewController;
        controller.linkedDevicesTableViewController = self;
    }
}

@end

NS_ASSUME_NONNULL_END
