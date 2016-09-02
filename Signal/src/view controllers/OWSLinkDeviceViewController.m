//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSLinkDeviceViewController.h"
#import "OWSDeviceProvisioningURLParser.h"
#import "OWSLinkedDevicesTableViewController.h"
#import "SettingsTableViewController.h"
#import <SignalServiceKit/ECKeyPair+OWSPrivateKey.h>
#import <SignalServiceKit/OWSDeviceProvisioner.h>
#import <SignalServiceKit/TSStorageManager+IdentityKeyStore.h>
#import <SignalServiceKit/TSStorageManager+keyingMaterial.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSLinkDeviceViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = NSLocalizedString(@"Link New Device", "Navigation title when scanning QR code to add new device.");
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)didDetectQRCodeWithString:(NSString *)string
{
    NSString *title = NSLocalizedString(@"Link this device?", @"Alert title");
    NSString *linkingDescription = NSLocalizedString(@"This device will be able to see your groups and contacts, read "
                                                     @"all your messages, and send messages in your name.",
        @"Alert body confirmation when linking a new device");

    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
                                                                             message:linkingDescription
                                                                      preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                                 style:UIAlertActionStyleCancel
                               handler:^(UIAlertAction *action) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       [self.navigationController popViewControllerAnimated:YES];
                                   });
                               }];
    [alertController addAction:cancelAction];

    UIAlertAction *proceedAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Link New Device", nil)
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *action) {
                                                              [self provisionWithString:string];
                                                          }];
    [alertController addAction:proceedAction];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)provisionWithString:(NSString *)string
{
    OWSDeviceProvisioningURLParser *parser = [[OWSDeviceProvisioningURLParser alloc] initWithProvisioningURL:string];

    if (!parser.isValid) {
        DDLogError(@"Unable to parse provisioning params from QRCode: %@", string);
        return;
    }

    NSData *myPublicKey = [[TSStorageManager sharedManager] identityKeyPair].publicKey;
    NSData *myPrivateKey = [[TSStorageManager sharedManager] identityKeyPair].ows_privateKey;
    NSString *accountIdentifier = [TSStorageManager localNumber];

    OWSDeviceProvisioner *provisioner = [[OWSDeviceProvisioner alloc] initWithMyPublicKey:myPublicKey
                                                                             myPrivateKey:myPrivateKey
                                                                           theirPublicKey:parser.publicKey
                                                                   theirEphemeralDeviceId:parser.ephemeralDeviceId
                                                                        accountIdentifier:accountIdentifier];

    [provisioner provisionWithSuccess:^{
        DDLogInfo(@"Successfully provisioned device.");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.linkedDevicesTableViewController expectMoreDevices];
            [self.navigationController popToViewController:self.linkedDevicesTableViewController animated:YES];
        });
    }
        failure:^(NSError *error) {
            DDLogError(@"Failed to provision device with error: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self presentViewController:[self retryAlertControllerWithError:error
                                                                     retryBlock:^{
                                                                         [self provisionWithString:string];
                                                                     }]
                                   animated:YES
                                 completion:nil];
            });
        }];
}

- (UIAlertController *)retryAlertControllerWithError:(NSError *)error retryBlock:(void (^)())retryBlock
{
    NSString *title = NSLocalizedString(@"Linking Device Failed", @"Alert Title");
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
                                                                             message:error.localizedDescription
                                                                      preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *retryAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"RETRY_BUTTON_TEXT", nil)
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
                                                            retryBlock();
                                                        }];
    [alertController addAction:retryAction];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                                 style:UIAlertActionStyleCancel
                               handler:^(UIAlertAction *action) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                       [self dismissViewControllerAnimated:YES completion:nil];
                                   });
                               }];
    [alertController addAction:cancelAction];
    return alertController;
}

@end

NS_ASSUME_NONNULL_END
