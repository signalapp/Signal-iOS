//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "FingerprintViewScanController.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSFingerprint.h>
#import <SignalServiceKit/OWSFingerprintBuilder.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalUI/SignalUI-Swift.h>
#import <SignalUI/UIFont+OWS.h>
#import <SignalUI/UIView+SignalUI.h>
#import <SignalUI/UIViewController+Permissions.h>

NS_ASSUME_NONNULL_BEGIN

@interface FingerprintViewScanController () <QRCodeScanDelegate>

@property (nonatomic) SignalServiceAddress *recipientAddress;
@property (nonatomic) NSData *identityKey;
@property (nonatomic) OWSFingerprint *fingerprint;
@property (nonatomic) NSString *contactName;
@property (nonatomic) QRCodeScanViewController *qrCodeScanViewController;

@end

#pragma mark -

@implementation FingerprintViewScanController

- (void)configureWithRecipientAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    self.recipientAddress = address;

    OWSContactsManager *contactsManager = Environment.shared.contactsManager;
    self.contactName = [contactsManager displayNameForAddress:address];

    OWSRecipientIdentity *_Nullable recipientIdentity =
        [[OWSIdentityManager shared] recipientIdentityForAddress:address];
    OWSAssertDebug(recipientIdentity);
    // By capturing the identity key when we enter these views, we prevent the edge case
    // where the user verifies a key that we learned about while this view was open.
    self.identityKey = recipientIdentity.identityKey;

    OWSFingerprintBuilder *builder = [[OWSFingerprintBuilder alloc] initWithAccountManager:self.tsAccountManager
                                                                           contactsManager:contactsManager];
    self.fingerprint = [builder fingerprintWithTheirSignalAddress:address
                                                 theirIdentityKey:recipientIdentity.identityKey];
}

- (void)loadView
{
    [super loadView];

    self.title = NSLocalizedString(@"SCAN_QR_CODE_VIEW_TITLE", @"Title for the 'scan QR code' view.");

    [self createViews];
}

- (void)createViews
{
    self.view.backgroundColor = UIColor.blackColor;

    self.qrCodeScanViewController =
        [[QRCodeScanViewController alloc] initWithAppearance:QRCodeScanViewAppearanceNormal];
    self.qrCodeScanViewController.delegate = self;
    [self.view addSubview:self.qrCodeScanViewController.view];
    [self.qrCodeScanViewController.view autoPinWidthToSuperview];
    [self.qrCodeScanViewController.view autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [self addChildViewController:self.qrCodeScanViewController];

    UIView *footer = [UIView new];
    footer.backgroundColor = [UIColor colorWithWhite:0.25f alpha:1.f];
    [self.view addSubview:footer];
    [footer autoPinWidthToSuperview];
    [footer autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [footer autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.qrCodeScanViewController.view];

    UILabel *cameraInstructionLabel = [UILabel new];
    cameraInstructionLabel.text
        = NSLocalizedString(@"SCAN_CODE_INSTRUCTIONS", @"label presented once scanning (camera) view is visible.");
    cameraInstructionLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(14.f, 18.f)];
    cameraInstructionLabel.textColor = [UIColor whiteColor];
    cameraInstructionLabel.textAlignment = NSTextAlignmentCenter;
    cameraInstructionLabel.numberOfLines = 0;
    cameraInstructionLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [footer addSubview:cameraInstructionLabel];
    [cameraInstructionLabel autoPinWidthToSuperviewWithMargin:ScaleFromIPhone5To7Plus(16.f, 30.f)];
    CGFloat instructionsVMargin = ScaleFromIPhone5To7Plus(10.f, 20.f);
    [cameraInstructionLabel autoPinToBottomLayoutGuideOfViewController:self withInset:instructionsVMargin];
    [cameraInstructionLabel autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:instructionsVMargin];
}

#pragma mark - QRCodeScanDelegate

- (void)qrCodeScanViewDismiss:(QRCodeScanViewController *)qrCodeScanViewController
{
    OWSAssertIsOnMainThread();

    [self.navigationController popViewControllerAnimated:YES];
}

- (QRCodeScanOutcome)qrCodeScanViewScanned:(QRCodeScanViewController *)qrCodeScanViewController
                                qrCodeData:(nullable NSData *)qrCodeData
                              qrCodeString:(nullable NSString *)qrCodeString
{
    OWSAssertIsOnMainThread();

    if (qrCodeData == nil) {
        // Only accept QR codes with a valid data (not string) payload.
        return QRCodeScanOutcomeContinueScanning;
    }

    [self verifyCombinedFingerprintData:qrCodeData];

    // Stop scanning even if verification failed.
    return QRCodeScanOutcomeStopScanning;
}

- (void)verifyCombinedFingerprintData:(NSData *)combinedFingerprintData
{
    OWSAssertIsOnMainThread();
    
    NSError *error;
    if ([self.fingerprint matchesLogicalFingerprintsData:combinedFingerprintData error:&error]) {
        [self showVerificationSucceeded];
    } else {
        [self showVerificationFailedWithError:error];
    }
}

- (void)showVerificationSucceeded
{
    OWSAssertIsOnMainThread();
    
    [self.class showVerificationSucceeded:self
                              identityKey:self.identityKey
                         recipientAddress:self.recipientAddress
                              contactName:self.contactName
                                      tag:self.logTag];
}

- (void)showVerificationFailedWithError:(NSError *)error
{
    OWSAssertIsOnMainThread();
    
    [self.class showVerificationFailedWithError:error
        viewController:self
        retryBlock:^{ [self.qrCodeScanViewController tryToStartScanning]; }
        cancelBlock:^{ [self.navigationController popViewControllerAnimated:YES]; }
        tag:self.logTag];
}

+ (void)showVerificationSucceeded:(UIViewController *)viewController
                      identityKey:(NSData *)identityKey
                 recipientAddress:(SignalServiceAddress *)address
                      contactName:(NSString *)contactName
                              tag:(NSString *)tag
{
    OWSAssertIsOnMainThread();    
    OWSAssertDebug(viewController);
    OWSAssertDebug(identityKey.length > 0);
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(contactName.length > 0);
    OWSAssertDebug(tag.length > 0);

    OWSLogInfo(@"%@ Successfully verified safety numbers.", tag);

    NSString *successTitle = NSLocalizedString(@"SUCCESSFUL_VERIFICATION_TITLE", nil);
    NSString *descriptionFormat = NSLocalizedString(
        @"SUCCESSFUL_VERIFICATION_DESCRIPTION", @"Alert body after verifying privacy with {{other user's name}}");
    NSString *successDescription = [NSString stringWithFormat:descriptionFormat, contactName];
    ActionSheetController *alert = [[ActionSheetController alloc] initWithTitle:successTitle
                                                                        message:successDescription];
    [alert addAction:[[ActionSheetAction alloc]
                         initWithTitle:NSLocalizedString(@"FINGERPRINT_SCAN_VERIFY_BUTTON",
                                           @"Button that marks user as verified after a successful fingerprint scan.")
                                 style:ActionSheetActionStyleDefault
                               handler:^(ActionSheetAction *action) {
                                   [OWSIdentityManager.shared setVerificationState:OWSVerificationStateVerified
                                                                       identityKey:identityKey
                                                                           address:address
                                                             isUserInitiatedChange:YES
                                                                  authedAccount:AuthedAccount.implicit];
                                   [viewController dismissViewControllerAnimated:true completion:nil];
                               }]];
    ActionSheetAction *dismissAction =
        [[ActionSheetAction alloc] initWithTitle:CommonStrings.dismissButton
                                           style:ActionSheetActionStyleDefault
                                         handler:^(ActionSheetAction *action) {
                                             [viewController dismissViewControllerAnimated:true completion:nil];
                                         }];
    [alert addAction:dismissAction];

    [viewController presentActionSheet:alert];
}

+ (void)showVerificationFailedWithError:(NSError *)error
                         viewController:(UIViewController *)viewController
                             retryBlock:(void (^_Nullable)(void))retryBlock
                            cancelBlock:(void (^_Nonnull)(void))cancelBlock
                                    tag:(NSString *)tag
{
    OWSAssertDebug(viewController);
    OWSAssertDebug(cancelBlock);
    OWSAssertDebug(tag.length > 0);

    OWSLogInfo(@"%@ Failed to verify safety numbers.", tag);

    NSString *_Nullable failureTitle;
    if (error.code != OWSErrorCodeUserError) {
        failureTitle = NSLocalizedString(@"FAILED_VERIFICATION_TITLE", @"alert title");
    } // else no title. We don't want to show a big scary "VERIFICATION FAILED" when it's just user error.

    ActionSheetController *alert = [[ActionSheetController alloc] initWithTitle:failureTitle
                                                                        message:error.userErrorDescription];

    if (retryBlock) {
        [alert addAction:[[ActionSheetAction alloc] initWithTitle:[CommonStrings retryButton]
                                                            style:ActionSheetActionStyleDefault
                                                          handler:^(ActionSheetAction *action) {
                                                              retryBlock();
                                                          }]];
    }

    [alert addAction:[OWSActionSheets cancelAction]];

    [viewController presentActionSheet:alert];

    OWSLogWarn(@"%@ Identity verification failed with error: %@", tag, error);
}

- (void)dismissViewControllerAnimated:(BOOL)animated completion:(nullable void (^)(void))completion
{
    self.qrCodeScanViewController.view.hidden = YES;

    [super dismissViewControllerAnimated:animated completion:completion];
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIDevice.currentDevice.isIPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

@end

NS_ASSUME_NONNULL_END
