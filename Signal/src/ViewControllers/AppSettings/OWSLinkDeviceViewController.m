//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSLinkDeviceViewController.h"
#import "Cryptography.h"
#import "OWSDeviceProvisioningURLParser.h"
#import "OWSLinkedDevicesTableViewController.h"
#import "Signal-Swift.h"
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalServiceKit/OWSDevice.h>
#import <SignalServiceKit/OWSDeviceProvisioner.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSLinkDeviceViewController ()

@property (nonatomic) YapDatabaseConnection *dbConnection;
@property (nonatomic) IBOutlet UIView *qrScanningView;
@property (nonatomic) IBOutlet UILabel *scanningInstructionsLabel;
@property (nonatomic) OWSQRCodeScanningViewController *qrScanningController;
@property (nonatomic, readonly) OWSReadReceiptManager *readReceiptManager;

@end

@implementation OWSLinkDeviceViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.dbConnection = [[OWSPrimaryStorage sharedManager] newDatabaseConnection];

    // HACK to get full width preview layer
    CGRect oldFrame = self.qrScanningView.frame;
    self.qrScanningView.frame = CGRectMake(
        oldFrame.origin.x, oldFrame.origin.y, self.view.frame.size.width, self.view.frame.size.height / 2.0f - 32.0f);
    // END HACK to get full width preview layer

    self.scanningInstructionsLabel.text = NSLocalizedString(@"LINK_DEVICE_SCANNING_INSTRUCTIONS",
        @"QR Scanning screen instructions, placed alongside a camera view for scanning QR Codes");
    self.title
        = NSLocalizedString(@"LINK_NEW_DEVICE_TITLE", "Navigation title when scanning QR code to add new device.");
}

- (OWSProfileManager *)profileManager
{
    return [OWSProfileManager sharedManager];
}

- (OWSReadReceiptManager *)readReceiptManager
{
    return [OWSReadReceiptManager sharedManager];
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
    OWSDeviceProvisioningURLParser *parser = [[OWSDeviceProvisioningURLParser alloc] initWithProvisioningURL:string];
    if (!parser.isValid) {
        OWSLogError(@"Unable to parse provisioning params from QRCode: %@", string);

        NSString *title = NSLocalizedString(@"LINK_DEVICE_INVALID_CODE_TITLE", @"report an invalid linking code");
        NSString *body = NSLocalizedString(@"LINK_DEVICE_INVALID_CODE_BODY", @"report an invalid linking code");

        UIAlertController *alertController =
            [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *cancelAction =
            [UIAlertAction actionWithTitle:CommonStrings.cancelButton
                                     style:UIAlertActionStyleCancel
                                   handler:^(UIAlertAction *action) {
                                       dispatch_async(dispatch_get_main_queue(), ^{
                                           [self.navigationController popViewControllerAnimated:YES];
                                       });
                                   }];
        [alertController addAction:cancelAction];

        UIAlertAction *proceedAction =
            [UIAlertAction actionWithTitle:NSLocalizedString(@"LINK_DEVICE_RESTART", @"attempt another linking")
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *action) {
                                       [self.qrScanningController startCapture];
                                   }];
        [alertController addAction:proceedAction];

        [self presentViewController:alertController animated:YES completion:nil];
    } else {
        NSString *title = NSLocalizedString(
            @"LINK_DEVICE_PERMISSION_ALERT_TITLE", @"confirm the users intent to link a new device");
        NSString *linkingDescription
            = NSLocalizedString(@"LINK_DEVICE_PERMISSION_ALERT_BODY", @"confirm the users intent to link a new device");

        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
                                                                                 message:linkingDescription
                                                                          preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *cancelAction =
            [UIAlertAction actionWithTitle:CommonStrings.cancelButton
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
                                       [self provisionWithParser:parser];
                                   }];
        [alertController addAction:proceedAction];

        [self presentViewController:alertController animated:YES completion:nil];
    }
}

- (void)provisionWithParser:(OWSDeviceProvisioningURLParser *)parser
{
    // Optimistically set this flag.
    [OWSDeviceManager.sharedManager setMayHaveLinkedDevices];

    ECKeyPair *_Nullable identityKeyPair = [[OWSIdentityManager sharedManager] identityKeyPair];
    OWSAssertDebug(identityKeyPair);
    NSData *myPublicKey = identityKeyPair.publicKey;
    NSData *myPrivateKey = identityKeyPair.privateKey;
    NSString *accountIdentifier = [TSAccountManager localNumber];
    NSData *myProfileKeyData = self.profileManager.localProfileKey.keyData;
    BOOL areReadReceiptsEnabled = self.readReceiptManager.areReadReceiptsEnabled;

    OWSDeviceProvisioner *provisioner = [[OWSDeviceProvisioner alloc] initWithMyPublicKey:myPublicKey
                                                                             myPrivateKey:myPrivateKey
                                                                           theirPublicKey:parser.publicKey
                                                                   theirEphemeralDeviceId:parser.ephemeralDeviceId
                                                                        accountIdentifier:accountIdentifier
                                                                               profileKey:myProfileKeyData
                                                                      readReceiptsEnabled:areReadReceiptsEnabled];

    [provisioner
        provisionWithSuccess:^{
            OWSLogInfo(@"Successfully provisioned device.");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.linkedDevicesTableViewController expectMoreDevices];
                [self.navigationController popToViewController:self.linkedDevicesTableViewController animated:YES];

                // The service implementation of the socket connection caches the linked device state,
                // so all sync message sends will fail on the socket until it is cycled.
                [TSSocketManager.sharedManager cycleSocket];
            });
        }
        failure:^(NSError *error) {
            OWSLogError(@"Failed to provision device with error: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self presentViewController:[self retryAlertControllerWithError:error
                                                                     retryBlock:^{
                                                                         [self provisionWithParser:parser];
                                                                     }]
                                   animated:YES
                                 completion:nil];
            });
        }];
}

- (UIAlertController *)retryAlertControllerWithError:(NSError *)error retryBlock:(void (^)(void))retryBlock
{
    NSString *title = NSLocalizedString(@"LINKING_DEVICE_FAILED_TITLE", @"Alert Title");
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title
                                                                             message:error.localizedDescription
                                                                      preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *retryAction = [UIAlertAction actionWithTitle:[CommonStrings retryButton]
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
                                                            retryBlock();
                                                        }];
    [alertController addAction:retryAction];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:CommonStrings.cancelButton
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
