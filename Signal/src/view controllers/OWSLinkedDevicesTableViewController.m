//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSLinkedDevicesTableViewController.h"
#import "OWSDeviceTableViewCell.h"
#import "OWSLinkDeviceViewController.h"
#import <SignalServiceKit/OWSDevice.h>
#import <SignalServiceKit/OWSDevicesService.h>

@interface OWSLinkedDevicesTableViewController ()

@property NSArray<OWSDevice *> *secondaryDevices;

@end

int const OWSLinkedDevicesTableViewControllerSectionExistingDevices = 0;
int const OWSLinkedDevicesTableViewControllerSectionAddDevice = 1;

@implementation OWSLinkedDevicesTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.expectMoreDevices = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 70;

    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(refreshDevices) forControlEvents:UIControlEventValueChanged];

    // Since this table is primarily for deleting items...
    [self setEditing:YES animated:NO];
    // So we can still tap on "add new device"
    self.tableView.allowsSelectionDuringEditing = YES;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.secondaryDevices = [OWSDevice secondaryDevices];

    // If we're returning from just adding a device, show that something's happening.
    if (self.expectMoreDevices) {
        [self.refreshControl beginRefreshing];
        [self.tableView setContentOffset:CGPointMake(0, -self.refreshControl.frame.size.height) animated:NO];
    }
    [self refreshDevices];
}

- (void)refreshDevices
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[OWSDevicesService new] getDevicesWithSuccess:^(NSArray<OWSDevice *> *devices) {
            if (devices.count > [OWSDevice numberOfKeysInCollection]) {
                // Got our new device, we can stop refreshing.
                self.expectMoreDevices = NO;
            }
            [OWSDevice replaceAll:devices];
            self.secondaryDevices = [OWSDevice secondaryDevices];

            if (self.expectMoreDevices) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC),
                    dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                    ^{
                        [self refreshDevices];
                    });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.refreshControl endRefreshing];
                    [self.tableView reloadData];
                });
            }
        }
            failure:^(NSError *error) {
                DDLogError(@"Failed to fetch devices in linkedDevices controller with error: %@", error);

                NSString *alertTitle = NSLocalizedString(
                    @"Failed to update device list.", @"Alert title that can occur when viewing device manager.");

                UIAlertController *alertController =
                    [UIAlertController alertControllerWithTitle:alertTitle
                                                        message:error.localizedDescription
                                                 preferredStyle:UIAlertControllerStyleAlert];

                NSString *retryTitle = NSLocalizedString(
                    @"RETRY_BUTTON_TEXT", @"Generic text for button that retries whatever the last action was.");
                UIAlertAction *retryAction = [UIAlertAction actionWithTitle:retryTitle
                                                                      style:UIAlertActionStyleDefault
                                                                    handler:^(UIAlertAction *action) {
                                                                        [self refreshDevices];
                                                                    }];
                [alertController addAction:retryAction];

                NSString *dismissTitle
                    = NSLocalizedString(@"DISMISS_BUTTON_TEXT", @"Generic short text for button to dismiss a dialog");
                UIAlertAction *dismissAction =
                    [UIAlertAction actionWithTitle:dismissTitle style:UIAlertActionStyleCancel handler:nil];
                [alertController addAction:dismissAction];

                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.refreshControl endRefreshing];
                    [self presentViewController:alertController animated:YES completion:nil];
                });
            }];
    });
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case OWSLinkedDevicesTableViewControllerSectionExistingDevices:
            return (NSInteger)self.secondaryDevices.count;

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
        return [tableView dequeueReusableCellWithIdentifier:@"AddNewDevice" forIndexPath:indexPath];
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

- (OWSDevice *)deviceForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == OWSLinkedDevicesTableViewControllerSectionExistingDevices) {
        return self.secondaryDevices[(NSUInteger)indexPath.row];
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
    return NSLocalizedString(@"Unlink", "Action title for unlinking a device");
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        OWSDevice *device = [self deviceForRowAtIndexPath:indexPath];
        [self touchedUnlinkControlForDevice:device
                                    success:^{
                                        DDLogInfo(@"Removing unlinked device with deviceId: %ld", device.deviceId);
                                        [device remove];
                                        self.secondaryDevices = [OWSDevice secondaryDevices];
                                        [tableView deleteRowsAtIndexPaths:@[ indexPath ]
                                                         withRowAnimation:UITableViewRowAnimationFade];
                                    }];
    }
}

- (void)touchedUnlinkControlForDevice:(OWSDevice *)device success:(void (^)())successCallback
{
    NSString *confirmationTitleFormat
        = NSLocalizedString(@"Unlink \"%@\"?", @"Alert title for confirming device deletion");
    NSString *confirmationTitle = [NSString stringWithFormat:confirmationTitleFormat, device.name];
    NSString *confirmationMessage
        = NSLocalizedString(@"By unlinking this device, it will no longer be able to send or receive messages.",
            @"Alert description shown to confirm unlinking a device.");
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:confirmationTitle
                                                                             message:confirmationMessage
                                                                      preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alertController addAction:cancelAction];

    UIAlertAction *unlinkAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"Unlink", "Action title for unlinking a device")
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
                                      NSString *title = NSLocalizedString(@"Signal was unable to delete your device.",
                                          @"Alert title when unlinking device fails");
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

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.destinationViewController isKindOfClass:[OWSLinkDeviceViewController class]]) {
        OWSLinkDeviceViewController *controller = (OWSLinkDeviceViewController *)segue.destinationViewController;
        controller.linkedDevicesTableViewController = self;
    }
}

@end
