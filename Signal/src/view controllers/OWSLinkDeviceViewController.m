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

@interface OWSLinkDeviceViewController ()

@property (strong, nonatomic) IBOutlet UIView *qrScanningView;
@property (strong, nonatomic) IBOutlet UILabel *scanningInstructionsLabel;
@property (strong, nonatomic) OWSQRCodeScanningViewController *qrScanningController;

@end

@implementation OWSLinkDeviceViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    // HACK to get full width preview layer
    CGRect oldFrame = self.qrScanningView.frame;
    self.qrScanningView.frame = CGRectMake(
        oldFrame.origin.x, oldFrame.origin.y, self.view.frame.size.width, self.view.frame.size.height / 2.0f - 32.0f);
    // END HACK to get full width preview layer

    self.scanningInstructionsLabel.text = NSLocalizedString(@"LINK_DEVICE_SCANNING_INSTRUCTIONS",
        @"QR Scanning screen instructions, placed alongside a camera view for scanning QRCodes");
    self.title
        = NSLocalizedString(@"LINK_NEW_DEVICE_TITLE", "Navigation title when scanning QR code to add new device.");
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.qrScanningController startCapture];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(nullable id)sender
{
    if ([segue.identifier isEqualToString:@"embedDeviceQRScanner"]) {
        OWSQRCodeScanningViewController *qrScanningController
            = (OWSQRCodeScanningViewController *)segue.destinationViewController;
        qrScanningController.scanDelegate = self;
        self.qrScanningController = qrScanningController;
    }
}


// pragma mark - OWSQRScannerDelegate
- (void)controller:(OWSQRCodeScanningViewController *)controller didDetectQRCodeWithString:(NSString *)string
{
    NSString *title
        = NSLocalizedString(@"LINK_DEVICE_PERMISSION_ALERT_TITLE", @"confirm the users intent to link a new device");
    NSString *linkingDescription
        = NSLocalizedString(@"LINK_DEVICE_PERMISSION_ALERT_BODY", @"confirm the users intent to link a new device");

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

    UIAlertAction *proceedAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"CONFIRM_LINK_NEW_DEVICE_ACTION", @"Button text")
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
    NSString *title = NSLocalizedString(@"LINKING_DEVICE_FAILED_TITLE", @"Alert Title");
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
