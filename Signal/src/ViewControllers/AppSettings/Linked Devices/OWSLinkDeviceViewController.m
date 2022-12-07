//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSLinkDeviceViewController.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalServiceKit/OWSDevice.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSReceiptManager.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSLinkDeviceViewController () <QRCodeScanDelegate>

@property (nonatomic) UIView *qrScanningView;
@property (nonatomic) UILabel *scanningInstructionsLabel;
@property (nonatomic) QRCodeScanViewController *qrCodeScanViewController;
@property (nonatomic, readonly) OWSReceiptManager *receiptManager;

@end

@implementation OWSLinkDeviceViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    UIImage *heroImage = [UIImage imageNamed:@"ic_devices_ios"];
    OWSAssertDebug(heroImage);
    UIImageView *heroImageView = [[UIImageView alloc] initWithImage:heroImage];
    [heroImageView autoSetDimensionsToSize:heroImage.size];

    self.scanningInstructionsLabel = [UILabel new];
    self.scanningInstructionsLabel.text = NSLocalizedString(@"LINK_DEVICE_SCANNING_INSTRUCTIONS",
        @"QR Scanning screen instructions, placed alongside a camera view for scanning QR Codes");
    self.scanningInstructionsLabel.font = UIFont.ows_dynamicTypeCaption1Font;
    self.scanningInstructionsLabel.numberOfLines = 0;
    self.scanningInstructionsLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.scanningInstructionsLabel.textAlignment = NSTextAlignmentCenter;

    self.qrCodeScanViewController = [[QRCodeScanViewController alloc] initWithAppearance:QRCodeScanViewAppearanceNormal];
    self.qrCodeScanViewController.delegate = self;
    [self.view addSubview:self.qrCodeScanViewController.view];
    [self.qrCodeScanViewController.view autoPinEdgeToSuperviewEdge:ALEdgeLeading];
    [self.qrCodeScanViewController.view autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
    [self.qrCodeScanViewController.view autoPinToTopLayoutGuideOfViewController:self withInset:0.f];
    [self.qrCodeScanViewController.view autoPinToSquareAspectRatio];
    [self addChildViewController:self.qrCodeScanViewController];

    UIView *bottomView = [UIView new];
    [self.view addSubview:bottomView];
    [bottomView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.qrCodeScanViewController.view];
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

#if TESTABLE_BUILD
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LocalizationNotNeeded(@"ENTER")
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(manuallyEnterLinkURL)];
#endif
}

#pragma mark -

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (!UIDevice.currentDevice.isIPad) {
        [UIDevice.currentDevice ows_setOrientation:UIDeviceOrientationPortrait];
    }
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];

    self.view.backgroundColor = Theme.backgroundColor;
    self.scanningInstructionsLabel.textColor = Theme.primaryTextColor;
}

#pragma mark - QRCodeScanDelegate

- (void)qrCodeScanViewDismiss:(QRCodeScanViewController *)qrCodeScanViewController
{
    OWSAssertIsOnMainThread();
    
    [self popToLinkedDeviceList];
}

- (QRCodeScanOutcome)qrCodeScanViewScanned:(QRCodeScanViewController *)qrCodeScanViewController
                   qrCodeData:(nullable NSData *)qrCodeData
                 qrCodeString:(nullable NSString *)qrCodeString
{
    OWSAssertIsOnMainThread();
    
    if (qrCodeString == nil) {
        // Only accept QR codes with a valid string payload.
        return QRCodeScanOutcomeContinueScanning;
    }

    DeviceProvisioningURL *url = [[DeviceProvisioningURL alloc] initWithUrlString:qrCodeString];
    if (url == nil) {
        OWSLogError(@"Unable to parse provisioning params from QRCode: %@", qrCodeString);

        NSString *title = NSLocalizedString(@"LINK_DEVICE_INVALID_CODE_TITLE", @"report an invalid linking code");
        NSString *body = NSLocalizedString(@"LINK_DEVICE_INVALID_CODE_BODY", @"report an invalid linking code");

        ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:title message:body];

        ActionSheetAction *cancelAction =
            [[ActionSheetAction alloc] initWithTitle:CommonStrings.cancelButton
                                               style:ActionSheetActionStyleCancel
                                             handler:^(ActionSheetAction *action) {
                                                 dispatch_async(dispatch_get_main_queue(), ^{
                                                     [self popToLinkedDeviceList];
                                                 });
                                             }];
        [actionSheet addAction:cancelAction];

        ActionSheetAction *proceedAction = [[ActionSheetAction alloc]
            initWithTitle:NSLocalizedString(@"LINK_DEVICE_RESTART", @"attempt another linking")
                    style:ActionSheetActionStyleDefault
                  handler:^(ActionSheetAction *action) {
                    [self.qrCodeScanViewController tryToStartScanning];
                  }];
        [actionSheet addAction:proceedAction];

        [self presentActionSheet:actionSheet];
    } else {
        [self confirmProvisioningWithUrl:url];
    }
    
    return QRCodeScanOutcomeStopScanning;
}

- (void)confirmProvisioningWithUrl:(DeviceProvisioningURL *)deviceProvisioningURL
{
    NSString *title = NSLocalizedString(
        @"LINK_DEVICE_PERMISSION_ALERT_TITLE", @"confirm the users intent to link a new device");
    NSString *linkingDescription
        = NSLocalizedString(@"LINK_DEVICE_PERMISSION_ALERT_BODY", @"confirm the users intent to link a new device");

    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:title
                                                                              message:linkingDescription];

    ActionSheetAction *cancelAction =
        [[ActionSheetAction alloc] initWithTitle:CommonStrings.cancelButton
                                           style:ActionSheetActionStyleCancel
                                         handler:^(ActionSheetAction *action) {
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 [self popToLinkedDeviceList];
                                             });
                                         }];
    [actionSheet addAction:cancelAction];

    ActionSheetAction *proceedAction = [[ActionSheetAction alloc]
        initWithTitle:NSLocalizedString(@"CONFIRM_LINK_NEW_DEVICE_ACTION", @"Button text")
                style:ActionSheetActionStyleDefault
              handler:^(ActionSheetAction *action) {
                  [self provisionWithUrl:deviceProvisioningURL];
              }];
    [actionSheet addAction:proceedAction];

    [self presentActionSheet:actionSheet];
}

- (void)provisionWithUrl:(DeviceProvisioningURL *)deviceProvisioningUrl
{
    // Optimistically set this flag.
    [OWSDeviceManager.shared setMayHaveLinkedDevices];

    ECKeyPair *_Nullable aciIdentityKeyPair = [[OWSIdentityManager shared] identityKeyPairForIdentity:OWSIdentityACI];
    OWSAssertDebug(aciIdentityKeyPair);
    ECKeyPair *_Nullable pniIdentityKeyPair = [[OWSIdentityManager shared] identityKeyPairForIdentity:OWSIdentityPNI];
    SignalServiceAddress *accountAddress = [TSAccountManager localAddress];
    NSUUID *_Nullable pni = [TSAccountManager shared].localPni;
    NSData *myProfileKeyData = self.profileManager.localProfileKey.keyData;
    BOOL areReadReceiptsEnabled = self.receiptManager.areReadReceiptsEnabled;

    OWSDeviceProvisioner *provisioner = [[OWSDeviceProvisioner alloc] initWithMyAciIdentityKeyPair:aciIdentityKeyPair
                                                                              myPniIdentityKeyPair:pniIdentityKeyPair
                                                                                    theirPublicKey:deviceProvisioningUrl.publicKey
                                                                            theirEphemeralDeviceId:deviceProvisioningUrl.ephemeralDeviceId
                                                                                    accountAddress:accountAddress
                                                                                               pni:pni
                                                                                        profileKey:myProfileKeyData
                                                                               readReceiptsEnabled:areReadReceiptsEnabled];

    [provisioner
        provisionWithSuccess:^{
            OWSLogInfo(@"Successfully provisioned device.");
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate expectMoreDevices];
                [self popToLinkedDeviceList];

                if (OWSWebSocket.verboseLogging) {
                    OWSLogInfo(@"");
                }
                
                // The service implementation of the socket connection caches the linked device state,
                // so all sync message sends will fail on the socket until it is cycled.
                [SocketManager.shared cycleSocket];

                // Fetch the local profile to determine if all
                // linked devices support UD.
                [self.profileManager fetchLocalUsersProfile];
            });
        }
        failure:^(NSError *error) {
            OWSLogError(@"Failed to provision device with error: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self presentActionSheet:[self retryActionSheetControllerWithError:error
                                                                        retryBlock:^{
                                                                            [self provisionWithUrl:deviceProvisioningUrl];
                                                                        }]];
            });
        }];
}

- (ActionSheetController *)retryActionSheetControllerWithError:(NSError *)error retryBlock:(void (^)(void))retryBlock
{
    NSString *title = NSLocalizedString(@"LINKING_DEVICE_FAILED_TITLE", @"Alert Title");
    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:title
                                                                              message:error.userErrorDescription];

    ActionSheetAction *retryAction = [[ActionSheetAction alloc] initWithTitle:[CommonStrings retryButton]
                                                                        style:ActionSheetActionStyleDefault
                                                                      handler:^(ActionSheetAction *action) {
                                                                          retryBlock();
                                                                      }];
    [actionSheet addAction:retryAction];

    ActionSheetAction *cancelAction = [[ActionSheetAction alloc] initWithTitle:CommonStrings.cancelButton
                                                                         style:ActionSheetActionStyleCancel
                                                                       handler:^(ActionSheetAction *action) {
                                                                           dispatch_async(dispatch_get_main_queue(), ^{
                                                                               [self dismissViewControllerAnimated:YES
                                                                                                        completion:nil];
                                                                           });
                                                                       }];
    [actionSheet addAction:cancelAction];
    return actionSheet;
}

- (void)popToLinkedDeviceList
{
    [self.navigationController popViewControllerWithAnimated:YES
                                                  completion:^{
                                                      [UIViewController attemptRotationToDeviceOrientation];
                                                  }];
}

#if TESTABLE_BUILD
- (IBAction)manuallyEnterLinkURL
{
    UIAlertController *alertController = [UIAlertController
        alertControllerWithTitle:LocalizationNotNeeded(@"Manually enter linking code.")
                         message:LocalizationNotNeeded(@"Copy the URL represented by the QR code into the field below.")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alertController addTextFieldWithConfigurationHandler:nil];
    [alertController
        addAction:[UIAlertAction
                      actionWithTitle:CommonStrings.okayButton
                                style:UIAlertActionStyleDefault
                              handler:^(UIAlertAction *action) {
        NSString *qrCodeString = [alertController textFields].firstObject.text;
        [self qrCodeScanViewScanned:self.qrCodeScanViewController
                         qrCodeData:nil
                       qrCodeString:qrCodeString];
                              }]];
    [alertController addAction:[UIAlertAction actionWithTitle:CommonStrings.cancelButton
                                                        style:UIAlertActionStyleCancel
                                                      handler:nil]];
    [self presentViewController:alertController animated:YES completion:nil];
}
#endif

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIDevice.currentDevice.isIPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

@end

NS_ASSUME_NONNULL_END
