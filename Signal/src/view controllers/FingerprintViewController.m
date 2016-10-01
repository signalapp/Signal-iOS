//
//  FingerprintViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 02/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "FingerprintViewController.h"
#import "DJWActionSheet+OWS.h"
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/OWSFingerprint.h>
#import <SignalServiceKit/TSInfoMessage.h>
#import <SignalServiceKit/TSStorageManager+IdentityKeyStore.h>
#import <SignalServiceKit/TSStorageManager+SessionStore.h>
#import <SignalServiceKit/TSStorageManager+keyingMaterial.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface FingerprintViewController ()

@property (strong, nonatomic) TSStorageManager *storageManager;
@property (nonatomic) BOOL isPresentingDialog;
@property (strong, nonatomic) TSThread *thread;
@property (strong, nonatomic) OWSFingerprint *fingerprint;
@property (strong, nonatomic) NSString *contactName;
@property (strong, nonatomic) OWSQRCodeScanningViewController *qrScanningController;

@property (strong, nonatomic) IBOutlet UIView *qrScanningView;
@property (strong, nonatomic) IBOutlet UIView *scanningContainer;
@property (strong, nonatomic) IBOutlet UIView *instructionsContainer;
@property (strong, nonatomic) IBOutlet UIView *qrContainer;
@property (strong, nonatomic) IBOutlet UIView *privacyVerificationQRCodeFrame;
@property (strong, nonatomic) IBOutlet UIImageView *privacyVerificationQRCode;
@property (strong, nonatomic) IBOutlet UILabel *privacyVerificationFingerprint;
@property (strong, nonatomic) IBOutlet UILabel *instructionsLabel;
@property (strong, nonatomic) IBOutlet UILabel *titleLabel;
@property (strong, nonatomic) IBOutlet UIButton *scanButton;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *qrCodeCenterConstraint;

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
    self.storageManager = [TSStorageManager sharedManager];
    self.qrScanningView.hidden = YES;

    // HACK to get full width preview layer
    CGRect oldFrame = self.qrScanningView.frame;
    CGRect newFrame = CGRectMake(oldFrame.origin.x,
        oldFrame.origin.y,
        self.view.frame.size.width,
        self.view.frame.size.height / 2.0f - oldFrame.origin.y);
    self.qrScanningView.frame = newFrame;
    // END HACK to get full width preview layer

    self.titleLabel.text = NSLocalizedString(@"PRIVACY_VERIFICATION_TITLE", @"Navbar title");
    NSString *instructionsFormat = NSLocalizedString(@"PRIVACY_VERIFICATION_INSTRUCTIONS",
        @"Paragraph(s) shown alongside keying material when verifying privacy with {{contact name}}");
    self.instructionsLabel.text = [NSString stringWithFormat:instructionsFormat, self.contactName];

    self.scanButton.titleLabel.text = NSLocalizedString(@"SCAN_CODE_ACTION",
        @"Button label presented with camera icon while verifying privacy credentials. Shows the camera interface.");

    // Safety numbers and QR Code
    self.privacyVerificationFingerprint.text = self.fingerprint.displayableText;
    self.privacyVerificationQRCode.image = self.fingerprint.image;

    // Don't antialias QRCode
    self.privacyVerificationQRCode.layer.magnificationFilter = kCAFilterNearest;

    // Add session reset action.
    UILongPressGestureRecognizer *longpressToResetSession =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(didLongpressToResetSession:)];
    longpressToResetSession.minimumPressDuration = 1.0;
    [self.view addGestureRecognizer:longpressToResetSession];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    self.privacyVerificationQRCodeFrame.layer.masksToBounds = YES;
    self.privacyVerificationQRCodeFrame.layer.cornerRadius = self.privacyVerificationQRCodeFrame.frame.size.height / 2;
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

#pragma mark - Action
- (IBAction)closeButtonAction:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)didTouchUpInsideScanButton:(id)sender
{
    [self showScanner];
}

- (IBAction)didLongpressToResetSession:(id)sender
{
    if (!_isPresentingDialog) {
        _isPresentingDialog = YES;
        [DJWActionSheet showInView:self.view
                         withTitle:NSLocalizedString(@"FINGERPRINT_SHRED_KEYMATERIAL_CONFIRMATION", @"")
                 cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
            destructiveButtonTitle:nil
                 otherButtonTitles:@[ NSLocalizedString(@"FINGERPRINT_SHRED_KEYMATERIAL_BUTTON", @"") ]
                          tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                            _isPresentingDialog = NO;
                            if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                                DDLogDebug(@"User Cancelled");
                            } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                                DDLogDebug(@"Destructive button tapped");
                            } else {
                                switch (tappedButtonIndex) {
                                    case 0:
                                        [self resetSession];
                                        break;
                                    default:
                                        break;
                                }
                            }
                          }];
    }
}

- (void)showScanner
{
    DDLogInfo(@"%@ Showing Scanner", self.tag);
    self.qrScanningView.hidden = NO;

    // Recommended before animating a constraint.
    [self.view layoutIfNeeded];

    // Shift QRCode up within it's own frame, while shifting it's whole
    // frame down.
    self.qrCodeCenterConstraint.constant = 0.0f;
    [UIView animateWithDuration:0.4
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{

                         self.scanningContainer.frame = self.qrContainer.frame;
                         self.qrContainer.frame = self.instructionsContainer.frame;
                         self.instructionsContainer.alpha = 0.0f;
                         // animate constraint smoothly
                         [self.view layoutIfNeeded];
                     }
                     completion:nil];

    [self.qrScanningController startCapture];
}

- (void)resetSession
{
    DDLogInfo(@"%@ local user reset session", self.tag);
    [self.storageManager removeIdentityKeyForRecipient:self.fingerprint.theirStableId];
    [self.storageManager deleteAllSessionsForContact:self.fingerprint.theirStableId];

    [[[TSInfoMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                     inThread:self.thread
                                  messageType:TSInfoMessageTypeSessionDidEnd] save];

    [self dismissViewControllerAnimated:YES completion:nil];
}

// pragma mark - OWSQRScannerDelegate
- (void)controller:(OWSQRCodeScanningViewController *)controller didDetectQRCodeWithData:(NSData *)data;
{
    [self verifyCombinedFingerprintData:data];
}

- (void)verifyCombinedFingerprintData:(NSData *)combinedFingerprintData
{
    NSError *error;
    if ([self.fingerprint matchesCombinedFingerprintData:combinedFingerprintData error:&error]) {
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
            [UIAlertAction actionWithTitle:dismissText
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *_Nonnull action) {
                                       [self dismissViewControllerAnimated:YES completion:nil];
                                   }];
        [successAlertController addAction:dismissAction];

        [self presentViewController:successAlertController animated:YES completion:nil];
    } else {
        [self failVerificationWithError:error];
    }
}

- (void)failVerificationWithError:(NSError *)error
{
    NSString *failureTitle = NSLocalizedString(@"FAILED_VERIFICATION_TITLE", @"alert title");
    UIAlertController *failureAlertController =
        [UIAlertController alertControllerWithTitle:failureTitle
                                            message:error.localizedDescription
                                     preferredStyle:UIAlertControllerStyleAlert];

    NSString *cancelText = NSLocalizedString(@"TXT_CANCEL_TITLE", nil);
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:cancelText
                                                           style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction *_Nonnull action) {
                                                             [self dismissViewControllerAnimated:YES completion:nil];
                                                         }];
    [failureAlertController addAction:cancelAction];

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
