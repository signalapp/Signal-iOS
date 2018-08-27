//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSLinkedDevicesTableViewController.h"
#import "OWSDeviceTableViewCell.h"
#import "OWSLinkDeviceViewController.h"
#import "Signal-Swift.h"
#import "UIViewController+Permissions.h"
#import <SignalServiceKit/NSTimer+OWS.h>
#import <SignalServiceKit/OWSDevice.h>
#import <SignalServiceKit/OWSDevicesService.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/TSDatabaseView.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseViewConnection.h>
#import <YapDatabase/YapDatabaseViewMappings.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSLinkedDevicesTableViewController ()

@property (nonatomic) YapDatabaseConnection *dbConnection;
@property (nonatomic) YapDatabaseViewMappings *deviceMappings;
@property (nonatomic) NSTimer *pollingRefreshTimer;
@property (nonatomic) BOOL isExpectingMoreDevices;

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

    self.view.backgroundColor = Theme.backgroundColor;

    self.title = NSLocalizedString(@"LINKED_DEVICES_TITLE", @"Menu item and navbar title for the device manager");

    self.isExpectingMoreDevices = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    self.tableView.separatorColor = Theme.cellSeparatorColor;

    [self.tableView applyScrollViewInsetsFix];

    self.dbConnection = [[OWSPrimaryStorage sharedManager] newDatabaseConnection];
    [self.dbConnection beginLongLivedReadTransaction];
    self.deviceMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[ TSSecondaryDevicesGroup ]
                                                                     view:TSSecondaryDevicesDatabaseViewExtensionName];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.deviceMappings updateWithTransaction:transaction];
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:OWSPrimaryStorage.sharedManager.dbNotificationObject];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModifiedExternally:)
                                                 name:YapDatabaseModifiedExternallyNotification
                                               object:nil];

    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(refreshDevices) forControlEvents:UIControlEventValueChanged];

    [self setupEditButton];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshDevices];

    NSIndexPath *_Nullable selectedPath = [self.tableView indexPathForSelectedRow];
    if (selectedPath) {
        // HACK to unselect rows when swiping back
        // http://stackoverflow.com/questions/19379510/uitableviewcell-doesnt-get-deselected-when-swiping-back-quickly
        [self.tableView deselectRowAtIndexPath:selectedPath animated:animated];
    }
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
    [self.pollingRefreshTimer invalidate];
    self.pollingRefreshTimer = [NSTimer weakScheduledTimerWithTimeInterval:(10.0)target:wself
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
        [[OWSDevicesService new]
            getDevicesWithSuccess:^(NSArray<OWSDevice *> *devices) {
                // If we have more than one device; we may have a linked device.
                if (devices.count > 1) {
                    // Setting this flag here shouldn't be necessary, but we do so
                    // because the "cost" is low and it will improve robustness.
                    [OWSDeviceManager.sharedManager setMayHaveLinkedDevices];
                }

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
                OWSLogError(@"Failed to fetch devices in linkedDevices controller with error: %@", error);

                NSString *alertTitle = NSLocalizedString(
                    @"DEVICE_LIST_UPDATE_FAILED_TITLE", @"Alert title that can occur when viewing device manager.");

                UIAlertController *alertController =
                    [UIAlertController alertControllerWithTitle:alertTitle
                                                        message:error.localizedDescription
                                                 preferredStyle:UIAlertControllerStyleAlert];

                UIAlertAction *retryAction = [UIAlertAction actionWithTitle:[CommonStrings retryButton]
                                                                      style:UIAlertActionStyleDefault
                                                                    handler:^(UIAlertAction *action) {
                                                                        [wself refreshDevices];
                                                                    }];
                [alertController addAction:retryAction];

                UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:CommonStrings.dismissButton
                                                                        style:UIAlertActionStyleCancel
                                                                      handler:nil];
                [alertController addAction:dismissAction];

                dispatch_async(dispatch_get_main_queue(), ^{
                    [wself.refreshControl endRefreshing];
                    [wself presentViewController:alertController animated:YES completion:nil];
                });
            }];
    });
}

#pragma mark - Table view data source

- (void)yapDatabaseModifiedExternally:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    // External database modifications can't be converted into incremental updates,
    // so rebuild everything.  This is expensive and usually isn't necessary, but
    // there's no alternative.
    [self.dbConnection beginLongLivedReadTransaction];
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.deviceMappings updateWithTransaction:transaction];
    }];

    [self.tableView reloadData];
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    OWSLogVerbose(@"");

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
            OWSLogError(@"Unknown section: %ld", (long)section);
            return 0;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];

    if (indexPath.section == OWSLinkedDevicesTableViewControllerSectionAddDevice) {
        [self ows_askForCameraPermissions:^(BOOL granted) {
            if (!granted) {
                return;
            }
            [self performSegueWithIdentifier:@"LinkDeviceSegue" sender:self];
        }];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == OWSLinkedDevicesTableViewControllerSectionAddDevice) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AddNewDevice" forIndexPath:indexPath];
        [OWSTableItem configureCell:cell];
        cell.textLabel.text
            = NSLocalizedString(@"LINK_NEW_DEVICE_TITLE", @"Navigation title when scanning QR code to add new device.");
        cell.detailTextLabel.text
            = NSLocalizedString(@"LINK_NEW_DEVICE_SUBTITLE", @"Subheading for 'Link New Device' navigation");
        return cell;
    } else if (indexPath.section == OWSLinkedDevicesTableViewControllerSectionExistingDevices) {
        OWSDeviceTableViewCell *cell =
            [tableView dequeueReusableCellWithIdentifier:@"ExistingDevice" forIndexPath:indexPath];
        OWSDevice *device = [self deviceForRowAtIndexPath:indexPath];
        [cell configureWithDevice:device];
        return cell;
    } else {
        OWSLogError(@"Unknown section: %@", indexPath);
        return [UITableViewCell new];
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
        [self
            touchedUnlinkControlForDevice:device
                                  success:^{
                                      OWSLogInfo(@"Removing unlinked device with deviceId: %ld", (long)device.deviceId);
                                      [device remove];
                                  }];
    }
}

- (void)touchedUnlinkControlForDevice:(OWSDevice *)device success:(void (^)(void))successCallback
{
    NSString *confirmationTitleFormat
        = NSLocalizedString(@"UNLINK_CONFIRMATION_ALERT_TITLE", @"Alert title for confirming device deletion");
    NSString *confirmationTitle = [NSString stringWithFormat:confirmationTitleFormat, device.name];
    NSString *confirmationMessage
        = NSLocalizedString(@"UNLINK_CONFIRMATION_ALERT_BODY", @"Alert message to confirm unlinking a device");
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:confirmationTitle
                                                                             message:confirmationMessage
                                                                      preferredStyle:UIAlertControllerStyleAlert];

    [alertController addAction:[OWSAlerts cancelAction]];

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

- (void)unlinkDevice:(OWSDevice *)device success:(void (^)(void))successCallback
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
                                          [UIAlertAction actionWithTitle:[CommonStrings retryButton]
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^(UIAlertAction *aaction) {
                                                                     [self unlinkDevice:device success:successCallback];
                                                                 }];
                                      [alertController addAction:retryAction];
                                      [alertController addAction:[OWSAlerts cancelAction]];

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
