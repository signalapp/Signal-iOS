//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "FingerprintViewController.h"
#import "Environment.h"
#import "OWSBezierPathView.h"
#import "OWSConversationSettingsTableViewController.h"
#import "OWSQRCodeScanningViewController.h"
#import "Signal-Swift.h"
#import "UIUtil.h"
#import "UIViewController+CameraPermissions.h"
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSFingerprint.h>
#import <SignalServiceKit/OWSFingerprintBuilder.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/TSInfoMessage.h>
#import <SignalServiceKit/TSStorageManager+SessionStore.h>
#import <SignalServiceKit/TSStorageManager+keyingMaterial.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CustomLayoutBlock)();

@interface CustomLayoutView : UIView

@property (nonatomic) CustomLayoutBlock layoutBlock;

@end

#pragma mark -

@implementation CustomLayoutView

- (void)layoutSubviews
{
    self.layoutBlock();
}

@end

#pragma mark -

@interface FingerprintViewController () <OWSCompareSafetyNumbersActivityDelegate>

@property (nonatomic) TSStorageManager *storageManager;
@property (nonatomic) OWSFingerprint *fingerprint;
@property (nonatomic) NSString *contactName;
@property (nonatomic) OWSQRCodeScanningViewController *qrScanningController;

@property (nonatomic) UIBarButtonItem *shareButton;
@property (nonatomic) UIView *mainView;
@property (nonatomic) UIView *referenceView;
@property (nonatomic) UIView *cameraView;

@property (nonatomic) NSLayoutConstraint *verticalAlignmentConstraint;
@property (nonatomic) BOOL isScanning;

@end

@implementation FingerprintViewController

- (void)configureWithRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    self.storageManager = [TSStorageManager sharedManager];

    OWSContactsManager *contactsManager = [Environment getCurrent].contactsManager;
    self.contactName = [contactsManager displayNameForPhoneIdentifier:recipientId];

    OWSRecipientIdentity *_Nullable recipientIdentity =
        [[OWSIdentityManager sharedManager] recipientIdentityForRecipientId:recipientId];
    OWSAssert(recipientIdentity);

    OWSFingerprintBuilder *builder =
        [[OWSFingerprintBuilder alloc] initWithStorageManager:self.storageManager contactsManager:contactsManager];
    self.fingerprint =
        [builder fingerprintWithTheirSignalId:recipientId theirIdentityKey:recipientIdentity.identityKey];
}

- (void)loadView
{
    [super loadView];

    self.title = NSLocalizedString(@"PRIVACY_VERIFICATION_TITLE", @"Navbar title");

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(closeButton)];
    self.shareButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                     target:self
                                                                     action:@selector(didTapShareButton)];
    self.navigationItem.rightBarButtonItem = self.shareButton;

    [self createViews];
}

- (void)createViews
{
    UIColor *darkGrey = [UIColor colorWithRGBHex:0x404040];

    self.view.backgroundColor = [UIColor whiteColor];

    UIView *referenceView = [UIView new];
    self.referenceView = referenceView;
    [self.view addSubview:referenceView];
    [referenceView autoPinWidthToSuperview];
    [referenceView autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [referenceView autoPinToBottomLayoutGuideOfViewController:self withInset:0];

    UIView *mainView = [UIView new];
    self.mainView = mainView;
    mainView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:mainView];
    [mainView autoPinWidthToSuperview];
    [[NSLayoutConstraint constraintWithItem:mainView
                                  attribute:NSLayoutAttributeHeight
                                  relatedBy:NSLayoutRelationEqual
                                     toItem:referenceView
                                  attribute:NSLayoutAttributeHeight
                                 multiplier:1.0
                                   constant:0.f] autoInstall];
    [mainView
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(mainViewTapped:)]];
    mainView.userInteractionEnabled = YES;

    UIView *cameraView = [UIView new];
    self.cameraView = cameraView;
    cameraView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:cameraView];
    [cameraView autoPinWidthToSuperview];
    [cameraView autoPinEdge:ALEdgeLeft toEdge:ALEdgeLeft ofView:mainView];
    [cameraView autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:mainView];

    self.qrScanningController = [OWSQRCodeScanningViewController new];
    self.qrScanningController.scanDelegate = self;
    [cameraView addSubview:self.qrScanningController.view];
    [self.qrScanningController.view autoPinWidthToSuperview];
    [self.qrScanningController.view autoSetDimension:ALDimensionHeight toSize:270];
    [self.qrScanningController.view autoPinEdgeToSuperviewEdge:ALEdgeTop];

    UILabel *cameraInstructionLabel = [UILabel new];
    cameraInstructionLabel.text
        = NSLocalizedString(@"SCAN_CODE_INSTRUCTIONS", @"label presented once scanning (camera) view is visible.");
    cameraInstructionLabel.font = [UIFont ows_regularFontWithSize:14.f];
    cameraInstructionLabel.textColor = darkGrey;
    cameraInstructionLabel.textAlignment = NSTextAlignmentCenter;
    cameraInstructionLabel.numberOfLines = 0;
    cameraInstructionLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [cameraView addSubview:cameraInstructionLabel];
    [cameraInstructionLabel autoPinWidthToSuperviewWithMargin:16.f];
    [cameraInstructionLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:10.f];
    [cameraInstructionLabel autoPinEdge:ALEdgeTop
                                 toEdge:ALEdgeBottom
                                 ofView:self.qrScanningController.view
                             withOffset:10.f];

    // Scan Button
    UIView *scanButton = [UIView new];
    [scanButton
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(scanButtonTapped:)]];
    [mainView addSubview:scanButton];
    [scanButton autoPinWidthToSuperview];
    [scanButton autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:12.f];

    UILabel *scanButtonLabel = [UILabel new];
    scanButtonLabel.text = NSLocalizedString(@"SCAN_CODE_ACTION",
        @"Button label presented with camera icon while verifying privacy credentials. Shows the camera interface.");
    scanButtonLabel.font = [UIFont ows_regularFontWithSize:18.f];
    scanButtonLabel.textColor = darkGrey;
    [scanButton addSubview:scanButtonLabel];
    [scanButtonLabel autoHCenterInSuperview];
    [scanButtonLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    UIImage *scanButtonImage = [UIImage imageNamed:@"btnCamera--white"];
    OWSAssert(scanButtonImage);
    UIImageView *scanButtonImageView = [UIImageView new];
    scanButtonImageView.image = [scanButtonImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    scanButtonImageView.tintColor = darkGrey;

    [scanButton addSubview:scanButtonImageView];
    [scanButtonImageView autoHCenterInSuperview];
    [scanButtonImageView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [scanButtonImageView autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:scanButtonLabel withOffset:-5.f];

    // Instructions
    NSString *instructionsFormat = NSLocalizedString(@"PRIVACY_VERIFICATION_INSTRUCTIONS",
        @"Paragraph(s) shown alongside the safety number when verifying privacy with {{contact name}}");
    UILabel *instructionsLabel = [UILabel new];
    instructionsLabel.text = [NSString stringWithFormat:instructionsFormat, self.contactName];
    UIFont *instructionsFont = [UIFont ows_dynamicTypeBodyFont];
    instructionsFont = [instructionsFont fontWithSize:instructionsFont.pointSize * 0.65f];
    instructionsLabel.font = instructionsFont;
    instructionsLabel.textColor = darkGrey;
    instructionsLabel.textAlignment = NSTextAlignmentCenter;
    instructionsLabel.numberOfLines = 0;
    instructionsLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [mainView addSubview:instructionsLabel];
    [instructionsLabel autoPinWidthToSuperviewWithMargin:16.f];
    [instructionsLabel autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:scanButton withOffset:-20.f];

    // Fingerprint Label
    UILabel *fingerprintLabel = [UILabel new];
    fingerprintLabel.text = self.fingerprint.displayableText;
    fingerprintLabel.font = [UIFont fontWithName:@"Menlo-Regular" size:23.f];
    fingerprintLabel.textColor = darkGrey;
    fingerprintLabel.numberOfLines = 3;
    fingerprintLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    fingerprintLabel.adjustsFontSizeToFitWidth = YES;
    [fingerprintLabel
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(fingerprintLabelTapped:)]];
    fingerprintLabel.userInteractionEnabled = YES;
    [mainView addSubview:fingerprintLabel];
    [fingerprintLabel autoPinWidthToSuperviewWithMargin:36.f];
    [fingerprintLabel autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:instructionsLabel withOffset:-8.f];

    // Fingerprint Image
    CustomLayoutView *fingerprintView = [CustomLayoutView new];
    [mainView addSubview:fingerprintView];
    [fingerprintView autoPinWidthToSuperview];
    [fingerprintView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:10.f];
    [fingerprintView autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:fingerprintLabel withOffset:-10.f];
    [fingerprintView
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(fingerprintViewTapped:)]];
    fingerprintView.userInteractionEnabled = YES;

    OWSBezierPathView *fingerprintCircle = [OWSBezierPathView new];
    [fingerprintCircle setConfigureShapeLayerBlock:^(CAShapeLayer *layer, CGRect bounds) {
        layer.fillColor = darkGrey.CGColor;
        CGFloat size = MIN(bounds.size.width, bounds.size.height);
        CGRect circle = CGRectMake((bounds.size.width - size) * 0.5f, (bounds.size.height - size) * 0.5f, size, size);
        layer.path = [UIBezierPath bezierPathWithOvalInRect:circle].CGPath;
    }];
    [fingerprintView addSubview:fingerprintCircle];
    [fingerprintCircle autoPinWidthToSuperview];
    [fingerprintCircle autoPinHeightToSuperview];

    UIImageView *fingerprintImageView = [UIImageView new];
    fingerprintImageView.image = self.fingerprint.image;
    fingerprintImageView.layer.magnificationFilter = kCAFilterNearest;
    fingerprintImageView.layer.minificationFilter = kCAFilterNearest;
    [fingerprintView addSubview:fingerprintImageView];

    fingerprintView.layoutBlock = ^{
        CGFloat size = round(MIN(fingerprintView.width, fingerprintView.height) * 0.65f);
        fingerprintImageView.frame = CGRectMake(
            round((fingerprintView.width - size) * 0.5f), round((fingerprintView.height - size) * 0.5f), size, size);
    };

    [self updateLayoutForIsScanning:NO animated:NO];
}

- (void)showScanningViews
{
    [self updateLayoutForIsScanning:YES animated:YES];
}

- (void)hideScanningViews
{
    [self updateLayoutForIsScanning:NO animated:YES];
}

- (void)updateLayoutForIsScanning:(BOOL)isScanning animated:(BOOL)animated
{
    self.isScanning = isScanning;

    if (self.verticalAlignmentConstraint) {
        [NSLayoutConstraint deactivateConstraints:@[ self.verticalAlignmentConstraint ]];
    }
    if (isScanning) {
        self.verticalAlignmentConstraint =
            [self.cameraView autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:self.referenceView];
    } else {
        self.verticalAlignmentConstraint =
            [self.mainView autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:self.referenceView];
    }
    [self.view setNeedsLayout];

    // Show scanning views immediately.
    if (isScanning) {
        self.shareButton.enabled = NO;
        self.cameraView.hidden = NO;
    }

    void (^completion)() = ^{
        if (!isScanning) {
            // Hide scanning views after they are offscreen.
            self.shareButton.enabled = YES;
            self.cameraView.hidden = YES;
        }
    };

    if (animated) {
        [UIView animateWithDuration:0.4
            delay:0.0
            options:UIViewAnimationOptionCurveEaseInOut
            animations:^{
                [self.view layoutSubviews];
            }
            completion:^(BOOL finished) {
                if (finished) {
                    completion();
                }
            }];
    } else {
        completion();
    }
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

#pragma mark - HilightableLableDelegate

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

- (void)closeButton
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)didTapShareButton
{
    [self showSharingActivityWithCompletion:nil];
}

- (void)showScanner
{
    [self ows_askForCameraPermissions:^{
        
        // Camera stops capturing when "sharing" while in capture mode.
        // Also, it's less obvious whats being "shared" at this point,
        // so just disable sharing when in capture mode.

        DDLogInfo(@"%@ Showing Scanner", self.tag);

        [self showScanningViews];

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
        [UIAlertAction actionWithTitle:dismissText style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
            [self dismissViewControllerAnimated:true completion:nil];
    }];
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
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:dismissText style:UIAlertActionStyleCancel handler: ^(UIAlertAction *action){
        
        // Restore previous layout
        [self hideScanningViews];
    }];
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
    [self updateLayoutForIsScanning:NO animated:NO];
    [super dismissViewControllerAnimated:flag completion:completion];
}

- (void)scanButtonTapped:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state == UIGestureRecognizerStateRecognized) {
        [self showScanner];
    }
}

- (void)fingerprintLabelTapped:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state == UIGestureRecognizerStateRecognized) {
        if (self.isScanning) {
            [self hideScanningViews];
            return;
        }
        [self showSharingActivityWithCompletion:nil];
    }
}

- (void)fingerprintViewTapped:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state == UIGestureRecognizerStateRecognized) {
        if (self.isScanning) {
            [self hideScanningViews];
            return;
        }
        [self showSharingActivityWithCompletion:nil];
    }
}

- (void)mainViewTapped:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state == UIGestureRecognizerStateRecognized) {
        if (self.isScanning) {
            [self hideScanningViews];
        }
    }
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
