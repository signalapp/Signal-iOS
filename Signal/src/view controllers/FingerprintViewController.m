//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "FingerprintViewController.h"
#import "Environment.h"
#import "OWSConversationSettingsTableViewController.h"
#import "Signal-Swift.h"
#import "UIUtil.h"
#import "UIViewController+CameraPermissions.h"
#import "UIViewController+OWS.h"
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSFingerprint.h>
#import <SignalServiceKit/TSInfoMessage.h>
#import <SignalServiceKit/TSStorageManager+IdentityKeyStore.h>
#import <SignalServiceKit/TSStorageManager+SessionStore.h>
#import <SignalServiceKit/TSStorageManager+keyingMaterial.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface FingerprintViewController () <OWSHighlightableLabelDelegate, OWSCompareSafetyNumbersActivityDelegate>

@property (strong, nonatomic) TSStorageManager *storageManager;
@property (strong, nonatomic) TSThread *thread;
@property (strong, nonatomic) OWSFingerprint *fingerprint;
@property (strong, nonatomic) NSString *contactName;
@property (strong, nonatomic) OWSQRCodeScanningViewController *qrScanningController;

@property (strong, nonatomic) IBOutlet UINavigationBar *modalNavigationBar;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *dismissModalButton;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *shareButton;
@property (strong, nonatomic) IBOutlet UIView *qrScanningView;
@property (strong, nonatomic) IBOutlet UILabel *scanningInstructions;
@property (strong, nonatomic) IBOutlet UIView *scanningContainer;
@property (strong, nonatomic) IBOutlet UIView *instructionsContainer;
@property (strong, nonatomic) IBOutlet UIView *qrContainer;
@property (strong, nonatomic) IBOutlet UIView *privacyVerificationQRCodeFrame;
@property (strong, nonatomic) IBOutlet UIImageView *privacyVerificationQRCode;
@property (strong, nonatomic) IBOutlet OWSHighlightableLabel *privacyVerificationFingerprint;
@property (strong, nonatomic) IBOutlet UILabel *instructionsLabel;
@property (strong, nonatomic) IBOutlet UIButton *scanButton;

@end

@implementation FingerprintViewController

- (void)configureWithThread:(TSThread *)thread
                fingerprint:(OWSFingerprint *)fingerprint
                contactName:(NSString *)contactName
{
    self.thread = thread;
    self.fingerprint = fingerprint;
    self.contactName = contactName;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.navigationItem.leftBarButtonItem = self.dismissModalButton;
    self.navigationItem.rightBarButtonItem = self.shareButton;
    [self.modalNavigationBar pushNavigationItem:self.navigationItem animated:NO];

    // HACK for transparent navigation bar.
    [self.modalNavigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    self.modalNavigationBar.shadowImage = [UIImage new];
    self.modalNavigationBar.translucent = YES;

    self.storageManager = [TSStorageManager sharedManager];

    // HACK to get full width preview layer
    CGRect oldFrame = self.qrScanningView.frame;
    CGRect newFrame = CGRectMake(oldFrame.origin.x,
        oldFrame.origin.y,
        self.view.frame.size.width,
        self.view.frame.size.height / 2.0f - oldFrame.origin.y);
    self.qrScanningView.frame = newFrame;
    // END HACK to get full width preview layer

    self.title = NSLocalizedString(@"PRIVACY_VERIFICATION_TITLE", @"Navbar title");
    NSString *instructionsFormat = NSLocalizedString(@"PRIVACY_VERIFICATION_INSTRUCTIONS",
        @"Paragraph(s) shown alongside the safety number when verifying privacy with {{contact name}}");
    self.instructionsLabel.text = [NSString stringWithFormat:instructionsFormat, self.contactName];

    NSString *scanTitle = NSLocalizedString(@"SCAN_CODE_ACTION",
        @"Button label presented with camera icon while verifying privacy credentials. Shows the camera interface.");
    [self.scanButton setTitle:scanTitle forState:UIControlStateNormal];
    self.scanningInstructions.text
        = NSLocalizedString(@"SCAN_CODE_INSTRUCTIONS", @"label presented once scanning (camera) view is visible.");

    // Safety numbers and QR Code
    self.privacyVerificationFingerprint.text = self.fingerprint.displayableText;
    self.privacyVerificationQRCode.image = self.fingerprint.image;

    // Don't antialias QRCode
    self.privacyVerificationQRCode.layer.magnificationFilter = kCAFilterNearest;

    self.privacyVerificationFingerprint.delegate = self;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    // On iOS8, the QRCodeFrame hasn't been layed out yet (causing the QRCode to be hidden), force it here.
    [self.privacyVerificationQRCodeFrame setNeedsLayout];
    [self.privacyVerificationQRCodeFrame layoutIfNeeded];
    // Round QR Code.
    self.privacyVerificationQRCodeFrame.layer.masksToBounds = YES;
    self.privacyVerificationQRCodeFrame.layer.cornerRadius = self.privacyVerificationQRCodeFrame.frame.size.height / 2;
}

- (void)viewWillAppear:(BOOL)animated
{
    // In case we're returning from activity view that needed default system styles.
    [UIUtil applySignalAppearence];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:YES];
    if (self.dismissDelegate) {
        [self.dismissDelegate presentedModalWasDismissed];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(nullable id)sender
{
    if ([segue.identifier isEqualToString:@"embedIdentityQRScanner"]) {
        OWSQRCodeScanningViewController *qrScanningController
            = (OWSQRCodeScanningViewController *)segue.destinationViewController;
        self.qrScanningController = qrScanningController;
        qrScanningController.scanDelegate = self;
    }
}

#pragma mark - HilightableLableDelegate

- (void)didHighlightLabel:(OWSHighlightableLabel *)label completion:(nullable void (^)(void))completionHandler
{
    [self showSharingActivityWithCompletion:completionHandler];
}

- (void)showSharingActivityWithCompletion:(nullable void (^)(void))completionHandler
{
    DDLogDebug(@"%@ Sharing safety numbers", self.tag);

    OWSCompareSafetyNumbersActivity *compareActivity = [[OWSCompareSafetyNumbersActivity alloc] initWithDelegate:self];

    NSString *shareFormat = NSLocalizedString(@"SAFETY_NUMBER_SHARE_FORMAT", @"Snippet to share {{safety number}} with a friend. sent e.g. via SMS");
    NSString *shareString = [NSString stringWithFormat:shareFormat, self.fingerprint.displayableText];

    UIActivityViewController *activityController =
        [[UIActivityViewController alloc] initWithActivityItems:@[ shareString ]
                                          applicationActivities:@[ compareActivity ]];

    activityController.completionWithItemsHandler = ^void(UIActivityType __nullable activityType, BOOL completed, NSArray * __nullable returnedItems, NSError * __nullable activityError){
        if (completionHandler) {
            completionHandler();
        }
        [UIUtil applySignalAppearence];
    };

    // This value was extracted by inspecting `activityType` in the activityController.completionHandler
    NSString *const iCloudActivityType = @"com.apple.CloudDocsUI.AddToiCloudDrive";
    activityController.excludedActivityTypes = @[
        UIActivityTypePostToFacebook,
        UIActivityTypePostToWeibo,
        UIActivityTypeAirDrop,
        UIActivityTypePostToTwitter,
        iCloudActivityType // This isn't being excluded. RADAR https://openradar.appspot.com/27493621
    ];

    [UIUtil applyDefaultSystemAppearence];
    [self presentViewController:activityController animated:YES completion:nil];
}

#pragma mark - OWSCompareSafetyNumbersActivityDelegate

- (void)compareSafetyNumbersActivitySucceededWithActivity:(OWSCompareSafetyNumbersActivity *)activity
{
    [self showVerificationSucceeded];
}

- (void)compareSafetyNumbersActivity:(OWSCompareSafetyNumbersActivity *)activity failedWithError:(NSError *)error
{
    [self showVerificationFailedWithError:error];
}

#pragma mark - Action

- (IBAction)closeButtonAction:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)didTapShareButton
{
    [self showSharingActivityWithCompletion:nil];
}

- (IBAction)didTouchUpInsideScanButton:(id)sender
{
    [self showScanner];
}

- (void)showScanner
{
    // Camera stops capturing when "sharing" while in capture mode.
    // Also, it's less obvious whats being "shared" at this point,
    // so just disable sharing when in capture mode.
    self.shareButton.enabled = NO;

    [self ows_askForCameraPermissions:^{
        DDLogInfo(@"%@ Showing Scanner", self.tag);
        self.qrScanningView.hidden = NO;
        self.scanningInstructions.hidden = NO;
        [UIView animateWithDuration:0.4
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
                             self.scanningContainer.frame = self.qrContainer.frame;
                             self.qrContainer.frame = self.instructionsContainer.frame;
                             self.instructionsContainer.alpha = 0.0f;
                         }
                         completion:nil];
        
        [self.qrScanningController startCapture];
    }
                   alertActionHandler:nil];
}

#pragma mark - OWSQRScannerDelegate

- (void)controller:(OWSQRCodeScanningViewController *)controller didDetectQRCodeWithData:(NSData *)data
{
    [self verifyCombinedFingerprintData:data];
}

- (void)verifyCombinedFingerprintData:(NSData *)combinedFingerprintData
{
    NSError *error;
    if ([self.fingerprint matchesLogicalFingerprintsData:combinedFingerprintData error:&error]) {
        [self showVerificationSucceeded];
    } else {
        [self showVerificationFailedWithError:error];
    }
}

- (void)showVerificationSucceeded
{
    DDLogInfo(@"%@ Successfully verified privacy.", self.tag);
    NSString *successTitle = NSLocalizedString(@"SUCCESSFUL_VERIFICATION_TITLE", nil);
    NSString *dismissText = NSLocalizedString(@"DISMISS_BUTTON_TEXT", nil);
    NSString *descriptionFormat = NSLocalizedString(
        @"SUCCESSFUL_VERIFICATION_DESCRIPTION", @"Alert body after verifying privacy with {{other user's name}}");
    NSString *successDescription = [NSString stringWithFormat:descriptionFormat, self.contactName];
    UIAlertController *successAlertController =
        [UIAlertController alertControllerWithTitle:successTitle
                                            message:successDescription
                                     preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *dismissAction =
        [UIAlertAction actionWithTitle:dismissText style:UIAlertActionStyleDefault handler:nil];
    [successAlertController addAction:dismissAction];

    [self presentViewController:successAlertController animated:YES completion:nil];
}

- (void)showVerificationFailedWithError:(NSError *)error
{
    NSString *_Nullable failureTitle;
    if (error.code != OWSErrorCodeUserError) {
        failureTitle = NSLocalizedString(@"FAILED_VERIFICATION_TITLE", @"alert title");
    } // else no title. We don't want to show a big scary "VERIFICATION FAILED" when it's just user error.

    UIAlertController *failureAlertController =
        [UIAlertController alertControllerWithTitle:failureTitle
                                            message:error.localizedDescription
                                     preferredStyle:UIAlertControllerStyleAlert];

    NSString *dismissText = NSLocalizedString(@"DISMISS_BUTTON_TEXT", nil);
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:dismissText style:UIAlertActionStyleCancel handler:nil];
    [failureAlertController addAction:dismissAction];

    // TODO
    //        NSString retryText = NSLocalizedString(@"RETRY_BUTTON_TEXT", nil);
    //        UIAlertAction *retryAction = [UIAlertAction actionWithTitle:retryText style:UIAlertActionStyleDefault
    //        handler:^(UIAlertAction * _Nonnull action) {
    //
    //        }];
    //        [failureAlertController addAction:retryAction];
    [self presentViewController:failureAlertController animated:YES completion:nil];

    DDLogWarn(@"%@ Identity verification failed with error: %@", self.tag, error);
}

- (void)dismissViewControllerAnimated:(BOOL)flag completion:(nullable void (^)(void))completion
{
    self.qrScanningView.hidden = YES;
    [super dismissViewControllerAnimated:flag completion:completion];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
