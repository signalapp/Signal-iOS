//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSLinkDeviceViewController.h"
#import "OWSDeviceProvisioningURLParser.h"
#import "OWSLinkedDevicesTableViewController.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalServiceKit/OWSDevice.h>
#import <SignalServiceKit/OWSDeviceProvisioner.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSLinkDeviceViewController () <OWSQRScannerDelegate>

@property (nonatomic) UIView *qrScanningView;
@property (nonatomic) UILabel *scanningInstructionsLabel;
@property (nonatomic) OWSQRCodeScanningViewController *qrScanningController;
@property (nonatomic, readonly) OWSReadReceiptManager *readReceiptManager;

@end

@implementation OWSLinkDeviceViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = Theme.backgroundColor;

    UIImage *heroImage = [UIImage imageNamed:@"ic_devices_ios"];
    OWSAssertDebug(heroImage);
    UIImageView *heroImageView = [[UIImageView alloc] initWithImage:heroImage];
    [heroImageView autoSetDimensionsToSize:heroImage.size];

    self.scanningInstructionsLabel = [UILabel new];
    self.scanningInstructionsLabel.text = NSLocalizedString(@"LINK_DEVICE_SCANNING_INSTRUCTIONS",
        @"QR Scanning screen instructions, placed alongside a camera view for scanning QR Codes");
    self.scanningInstructionsLabel.textColor = Theme.primaryColor;
    self.scanningInstructionsLabel.font = UIFont.ows_dynamicTypeCaption1Font;
    self.scanningInstructionsLabel.numberOfLines = 0;
    self.scanningInstructionsLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.scanningInstructionsLabel.textAlignment = NSTextAlignmentCenter;

    self.qrScanningController = [OWSQRCodeScanningViewController new];
    self.qrScanningController.scanDelegate = self;
    [self.view addSubview:self.qrScanningController.view];
    [self.qrScanningController.view autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [self.qrScanningController.view autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    [self.qrScanningController.view autoPinToTopLayoutGuideOfViewController:self withInset:0.f];
    [self.qrScanningController.view autoPinToSquareAspectRatio];

    UIView *bottomView = [UIView new];
    [self.view addSubview:bottomView];
    [bottomView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.qrScanningController.view];
    [bottomView autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [bottomView autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    [bottomView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    UIStackView *bottomStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        heroImageView,
        self.scanningInstructionsLabel,
    ]];
    bottomStack.axis = UILayoutConstraintAxisVertical;
    bottomStack.alignment = UIStackViewAlignmentCenter;
    bottomStack.spacing = 2;
    bottomStack.layoutMarginsRelativeArrangement = YES;
    bottomStack.layoutMargins = UIEdgeInsetsMake(20, 20, 20, 20);
    [bottomView addSubview:bottomStack];
    [bottomStack autoPinWidthToSuperview];
    [bottomStack autoVCenterInSuperview];

    self.title
        = NSLocalizedString(@"LINK_NEW_DEVICE_TITLE", "Navigation title when scanning QR code to add new device.");
}

#pragma mark - Dependencies

- (OWSProfileManager *)profileManager
{
    return [OWSProfileManager sharedManager];
}

- (OWSReadReceiptManager *)readReceiptManager
{
    return [OWSReadReceiptManager sharedManager];
}

- (id<OWSUDManager>)udManager
{
    return SSKEnvironment.shared.udManager;
}

- (TSAccountManager *)tsAccountManager
{
    return TSAccountManager.sharedInstance;
}

- (TSSocketManager *)socketManager
{
    return SSKEnvironment.shared.socketManager;
}

#pragma mark -

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [UIDevice.currentDevice ows_setOrientation:UIInterfaceOrientationPortrait];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.qrScanningController startCapture];
    });
}

#pragma mark - OWSQRScannerDelegate

- (void)controller:(OWSQRCodeScanningViewController *)controller didDetectQRCodeWithString:(NSString *)string
{
    OWSDeviceProvisioningURLParser *parser = [[OWSDeviceProvisioningURLParser alloc] initWithProvisioningURL:string];
    if (!parser.isValid) {
        OWSLogError(@"Unable to parse provisioning params from QRCode: %@", string);

        NSString *title = NSLocalizedString(@"LINK_DEVICE_INVALID_CODE_TITLE", @"report an invalid linking code");
        NSString *body = NSLocalizedString(@"LINK_DEVICE_INVALID_CODE_BODY", @"report an invalid linking code");

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:CommonStrings.cancelButton
                                                               style:UIAlertActionStyleCancel
                                                             handler:^(UIAlertAction *action) {
                                                                 dispatch_async(dispatch_get_main_queue(), ^{
                                                                     [self popToLinkedDeviceList];
                                                                 });
                                                             }];
        [alert addAction:cancelAction];

        UIAlertAction *proceedAction =
            [UIAlertAction actionWithTitle:NSLocalizedString(@"LINK_DEVICE_RESTART", @"attempt another linking")
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *action) {
                                       [self.qrScanningController startCapture];
                                   }];
        [alert addAction:proceedAction];

        [self presentAlert:alert];
    } else {
        NSString *title = NSLocalizedString(
            @"LINK_DEVICE_PERMISSION_ALERT_TITLE", @"confirm the users intent to link a new device");
        NSString *linkingDescription
            = NSLocalizedString(@"LINK_DEVICE_PERMISSION_ALERT_BODY", @"confirm the users intent to link a new device");

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:linkingDescription
                                                                preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:CommonStrings.cancelButton
                                                               style:UIAlertActionStyleCancel
                                                             handler:^(UIAlertAction *action) {
                                                                 dispatch_async(dispatch_get_main_queue(), ^{
                                                                     [self popToLinkedDeviceList];
                                                                 });
                                                             }];
        [alert addAction:cancelAction];

        UIAlertAction *proceedAction =
            [UIAlertAction actionWithTitle:NSLocalizedString(@"CONFIRM_LINK_NEW_DEVICE_ACTION", @"Button text")
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *action) {
                                       [self provisionWithParser:parser];
                                   }];
        [alert addAction:proceedAction];

        [self presentAlert:alert];
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
    SignalServiceAddress *accountAddress = [TSAccountManager localAddress];
    NSData *myProfileKeyData = self.profileManager.localProfileKey.keyData;
    BOOL areReadReceiptsEnabled = self.readReceiptManager.areReadReceiptsEnabled;

    OWSDeviceProvisioner *provisioner = [[OWSDeviceProvisioner alloc] initWithMyPublicKey:myPublicKey
                                                                             myPrivateKey:myPrivateKey
                                                                           theirPublicKey:parser.publicKey
                                                                   theirEphemeralDeviceId:parser.ephemeralDeviceId
                                                                           accountAddress:accountAddress
                                                                               profileKey:myProfileKeyData
                                                                      readReceiptsEnabled:areReadReceiptsEnabled];

    [provisioner
        provisionWithSuccess:^{
            OWSLogInfo(@"Successfully provisioned device.");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.linkedDevicesTableViewController expectMoreDevices];
                [self popToLinkedDeviceList];

                // The service implementation of the socket connection caches the linked device state,
                // so all sync message sends will fail on the socket until it is cycled.
                [TSSocketManager.shared cycleSocket];

                // Fetch the local profile to determine if all
                // linked devices support UD.
                [self.profileManager fetchLocalUsersProfile];
            });
        }
        failure:^(NSError *error) {
            OWSLogError(@"Failed to provision device with error: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self presentAlert:[self retryAlertControllerWithError:error
                                                            retryBlock:^{
                                                                [self provisionWithParser:parser];
                                                            }]];
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

- (void)popToLinkedDeviceList
{
    [self.navigationController popViewControllerWithAnimated:YES
                                                  completion:^{
                                                      [UIViewController attemptRotationToDeviceOrientation];
                                                  }];
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

@end

NS_ASSUME_NONNULL_END
