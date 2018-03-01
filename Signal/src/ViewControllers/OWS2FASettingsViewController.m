//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWS2FASettingsViewController.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import "SignalMessaging.h"
#import <SignalMessaging/NSString+OWS.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/SignalMessaging.h>
#import <SignalMessaging/UIColor+OWS.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalServiceKit/OWS2FAManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWS2FASettingsViewController () <UITextFieldDelegate>

@property (nonatomic, weak) UIViewController *root2FAViewController;

@property (nonatomic) UITextField *pinTextfield;
@property (nonatomic) OWSTableViewController *tableViewController;

@end

#pragma mark -

@implementation OWS2FASettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.whiteColor;

    self.title = NSLocalizedString(@"ENABLE_2FA_VIEW_TITLE", @"Title for the 'enable two factor auth PIN' views.");

    [self createContents];
}

- (void)createContents
{
    for (UIView *subview in self.view.subviews) {
        [subview removeFromSuperview];
    }

    switch (self.mode) {
        case OWS2FASettingsMode_Status:
            [self createStatusContents];
            break;
        case OWS2FASettingsMode_SelectPIN:
            [self createSelectCodeContents];
            break;
        case OWS2FASettingsMode_ConfirmPIN:
            [self createConfirmCodeContents];
            break;
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    switch (self.mode) {
        case OWS2FASettingsMode_Status:
            break;
        case OWS2FASettingsMode_SelectPIN:
        case OWS2FASettingsMode_ConfirmPIN:
            OWSAssert(![OWS2FAManager.sharedManager is2FAEnabled]);
            break;
    }

    [super viewWillAppear:animated];

    if (self.mode == OWS2FASettingsMode_Status) {
        // Ever time we re-enter the "status" view, recreate its
        // contents wholesale since we may have just enabled or
        // disabled 2FA.
        [self createContents];
    } else {
        // If we're using a table, refresh its contents.
        [self updateTableContents];
    }

    [self updateNavigationItems];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    // If we're using a PIN textfield, select it.
    [self.pinTextfield becomeFirstResponder];
}

- (UILabel *)createLabelWithText:(NSString *)text
{
    UILabel *label = [UILabel new];
    label.textColor = [UIColor blackColor];
    label.text = text;
    label.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(14.f, 16.f)];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:label];
    return label;
}

- (void)createPinTextfield
{
    self.pinTextfield = [UITextField new];
    self.pinTextfield.textColor = [UIColor blackColor];
    switch (self.mode) {
        case OWS2FASettingsMode_SelectPIN:
            self.pinTextfield.placeholder = NSLocalizedString(@"ENABLE_2FA_VIEW_SELECT_PIN_DEFAULT_TEXT",
                @"Text field placeholder for 'two factor auth pin' when selecting a pin.");
            break;
        case OWS2FASettingsMode_ConfirmPIN:
            self.pinTextfield.placeholder = NSLocalizedString(@"ENABLE_2FA_VIEW_CONFIRM_PIN_DEFAULT_TEXT",
                @"Text field placeholder for 'two factor auth pin' when confirming a pin.");
            break;
        case OWS2FASettingsMode_Status:
            OWSFail(@"%@ invalid mode.", self.logTag) break;
    }
    self.pinTextfield.font = [UIFont ows_mediumFontWithSize:ScaleFromIPhone5To7Plus(30.f, 36.f)];
    self.pinTextfield.textAlignment = NSTextAlignmentCenter;
    self.pinTextfield.keyboardType = UIKeyboardTypeNumberPad;
    self.pinTextfield.delegate = self;
    self.pinTextfield.secureTextEntry = YES;
    self.pinTextfield.textAlignment = NSTextAlignmentCenter;
    [self.pinTextfield addTarget:self
                          action:@selector(textFieldDidChange:)
                forControlEvents:UIControlEventEditingChanged];
    [self.view addSubview:self.pinTextfield];
}

- (void)createTableView
{
    self.tableViewController = [OWSTableViewController new];
    [self.view addSubview:self.tableViewController.view];
}

- (void)createStatusContents
{
    const CGFloat kVSpacing = 30.f;

    // TODO: Add hero image?
    // TODO: Tweak background color?

    NSString *instructions = ([OWS2FAManager.sharedManager is2FAEnabled]
            ? NSLocalizedString(@"ENABLE_2FA_VIEW_STATUS_ENABLED_INSTRUCTIONS",
                  @"Indicates that user has 'two factor auth pin' enabled.")
            : NSLocalizedString(@"ENABLE_2FA_VIEW_STATUS_DISABLED_INSTRUCTIONS",
                  @"Indicates that user has 'two factor auth pin' disabled."));
    UILabel *instructionsLabel = [self createLabelWithText:instructions];

    [self createTableView];

    [instructionsLabel autoPinToTopLayoutGuideOfViewController:self withInset:kVSpacing];
    [instructionsLabel autoPinWidthToSuperviewWithMargin:self.hMargin];

    [self.tableViewController.view autoPinWidthToSuperview];
    [self.tableViewController.view autoPinEdge:ALEdgeTop
                                        toEdge:ALEdgeBottom
                                        ofView:instructionsLabel
                                    withOffset:kVSpacing];
    [self.tableViewController.view autoPinToBottomLayoutGuideOfViewController:self withInset:0];

    [self updateTableContents];
}

- (void)createSelectCodeContents
{
    [self createEnterPINContentsWithInstructions:NSLocalizedString(@"ENABLE_2FA_VIEW_SELECT_PIN_INSTRUCTIONS",
                                                     @"Indicates that user should select a 'two factor auth pin'.")];
}

- (void)createConfirmCodeContents
{
    [self
        createEnterPINContentsWithInstructions:NSLocalizedString(@"ENABLE_2FA_VIEW_CONFIRM_PIN_INSTRUCTIONS",
                                                   @"Indicates that user should confirm their 'two factor auth pin'.")];
}

- (CGFloat)hMargin
{
    return 20.f;
}

- (void)createEnterPINContentsWithInstructions:(NSString *)instructionsText
{
    const CGFloat kVSpacing = 30.f;

    UILabel *instructionsLabel = [self createLabelWithText:instructionsText];

    [self createPinTextfield];

    [instructionsLabel autoPinTopToSuperviewWithMargin:kVSpacing];
    [instructionsLabel autoPinWidthToSuperviewWithMargin:self.hMargin];

    //    CGFloat textFieldWidth = [self.pinTextfield sizeThatFits:CGSizeZero].width + 10.f;

    [self.pinTextfield autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:instructionsLabel withOffset:kVSpacing];
    [self.pinTextfield autoPinWidthToSuperviewWithMargin:self.hMargin];
    //    [self.pinTextfield autoSetDimension:ALDimensionWidth toSize:textFieldWidth];
    [self.pinTextfield autoHCenterInSuperview];

    UIView *underscoreView = [UIView new];
    underscoreView.backgroundColor = [UIColor colorWithWhite:0.5 alpha:1.f];
    [self.view addSubview:underscoreView];
    [underscoreView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.pinTextfield withOffset:3];
    [underscoreView autoPinWidthToSuperviewWithMargin:self.hMargin];
    //    [underscoreView autoSetDimension:ALDimensionWidth toSize:textFieldWidth];
    [underscoreView autoHCenterInSuperview];
    [underscoreView autoSetDimension:ALDimensionHeight toSize:1.f];

    [self updateNavigationItems];
}

- (void)updateTableContents
{
    __weak OWS2FASettingsViewController *weakSelf = self;

    // Only some modes use a table.
    switch (self.mode) {
        case OWS2FASettingsMode_Status: {
            OWSTableContents *contents = [OWSTableContents new];
            OWSTableSection *section = [OWSTableSection new];
            if ([OWS2FAManager.sharedManager is2FAEnabled]) {
                [section
                    addItem:[OWSTableItem disclosureItemWithText:
                                              NSLocalizedString(@"ENABLE_2FA_VIEW_DISABLE_2FA",
                                                  @"Label for the 'enable two-factor auth' item in the settings view")
                                                     actionBlock:^{
                                                         [weakSelf tryToDisable2FA];
                                                     }]];
            } else {
                [section
                    addItem:[OWSTableItem disclosureItemWithText:
                                              NSLocalizedString(@"ENABLE_2FA_VIEW_ENABLE_2FA",
                                                  @"Label for the 'enable two-factor auth' item in the settings view")
                                                     actionBlock:^{
                                                         [weakSelf showEnable2FAWorkUI];
                                                     }]];
            }
            [contents addSection:section];
            self.tableViewController.contents = contents;
            break;
        }
        case OWS2FASettingsMode_SelectPIN:
        case OWS2FASettingsMode_ConfirmPIN:
            return;
    }
}

- (BOOL)shouldHaveNextButton
{
    switch (self.mode) {
        case OWS2FASettingsMode_Status:
            return NO;
        case OWS2FASettingsMode_SelectPIN:
        case OWS2FASettingsMode_ConfirmPIN:
            return [self hasValidPin];
    }
}

- (void)updateNavigationItems
{
    // Note: This affects how the "back" button will look if another
    //       view is pushed on top of this one, not how the "back"
    //       button looks when this view is visible.
    self.navigationItem.backBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"VERIFICATION_BACK_BUTTON",
                                                   @"button text for back button on verification view")
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(backButtonWasPressed)];

    if (self.shouldHaveNextButton) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithTitle:NSLocalizedString(@"ENABLE_2FA_VIEW_NEXT_BUTTON",
                              @"Label for the 'next' button in the 'enable two factor auth' views.")
                    style:UIBarButtonItemStylePlain
                   target:self
                   action:@selector(nextButtonWasPressed)];
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
{
    // TODO: ?
    const NSUInteger kMaxPinLength = 14;

    // * We only want to let the user enter decimal digits.
    // * The user should be able to copy and paste freely.
    // * Invalid input should be simply ignored.
    //
    // We accomplish this by being permissive and trying to "take as much of the user
    // input as possible".
    //
    // * Always accept deletes.
    // * Ignore invalid input.
    // * Take partial input if possible.

    NSString *oldText = textField.text;
    // Construct the new contents of the text field by:
    // 1. Determining the "left" substring: the contents of the old text _before_ the deletion range.
    //    Filtering will remove non-decimal digit characters.
    NSString *left = [oldText substringToIndex:range.location].digitsOnly;
    // 2. Determining the "right" substring: the contents of the old text _after_ the deletion range.
    NSString *right = [oldText substringFromIndex:range.location + range.length].digitsOnly;
    // 3. Determining the "center" substring: the contents of the new insertion text.
    NSString *center = insertionText.digitsOnly;
    // 4. Construct the "raw" new text by concatenating left, center and right.
    NSString *textAfterChange = [[left stringByAppendingString:center] stringByAppendingString:right];
    // 5. Ensure we don't exceed the maximum length for a PIN.
    if (textAfterChange.length > kMaxPinLength) {
        textAfterChange = [textAfterChange substringToIndex:kMaxPinLength];
    }
    // 6. Construct the "formatted" new text by inserting a hyphen if necessary.
    // reformat the phone number, trying to keep the cursor beside the inserted or deleted digit
    textField.text = textAfterChange;
    NSUInteger cursorPositionAfterChange = MIN(left.length + center.length, textAfterChange.length);
    UITextPosition *pos =
        [textField positionFromPosition:textField.beginningOfDocument offset:(NSInteger)cursorPositionAfterChange];
    [textField setSelectedTextRange:[textField textRangeFromPosition:pos toPosition:pos]];

    [self updateNavigationItems];

    return NO;
}

- (void)textFieldDidChange:(id)sender
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [self updateNavigationItems];
}

#pragma mark - Events

- (void)nextButtonWasPressed
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    switch (self.mode) {
        case OWS2FASettingsMode_Status:
            OWSFail(@"%@ status mode should not have a next button.", self.logTag);
            return;
        case OWS2FASettingsMode_SelectPIN: {
            OWSAssert(self.hasValidPin);

            OWS2FASettingsViewController *vc = [OWS2FASettingsViewController new];
            vc.mode = OWS2FASettingsMode_ConfirmPIN;
            vc.candidatePin = self.pinTextfield.text;
            OWSAssert(self.root2FAViewController);
            vc.root2FAViewController = self.root2FAViewController;
            [self.navigationController pushViewController:vc animated:YES];
            break;
        }
        case OWS2FASettingsMode_ConfirmPIN: {
            OWSAssert(self.hasValidPin);

            if ([self.pinTextfield.text isEqualToString:self.candidatePin]) {
                [self tryToEnable2FA];
            } else {
                // Clear the PIN so that the user can try again.
                self.pinTextfield.text = nil;

                [OWSAlerts
                    showAlertWithTitle:NSLocalizedString(@"ALERT_ERROR_TITLE", @"")
                               message:NSLocalizedString(@"ENABLE_2FA_VIEW_PIN_DOES_NOT_MATCH",
                                           @"Error indicating that the entered 'two-factor auth PINs' do not match.")];
            }
            break;
        }
    }
}

- (BOOL)hasValidPin
{
    const NSUInteger kMinPinLength = 4;
    return self.pinTextfield.text.length >= kMinPinLength;
}

- (void)showEnable2FAWorkUI
{
    OWSAssert(![OWS2FAManager.sharedManager is2FAEnabled]);

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    OWS2FASettingsViewController *vc = [OWS2FASettingsViewController new];
    vc.mode = OWS2FASettingsMode_SelectPIN;
    vc.root2FAViewController = self;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tryToDisable2FA
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    __weak OWS2FASettingsViewController *weakSelf = self;

    [ModalActivityIndicatorViewController
        presentFromViewController:self
                        canCancel:NO
                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                      [OWS2FAManager.sharedManager disable2FAWithSuccess:^{
                          [modalActivityIndicator dismissWithCompletion:^{
                              // TODO: Should we show an alert?

                              [weakSelf updateTableContents];
                          }];
                      }
                          failure:^(NSError *error) {
                              [modalActivityIndicator dismissWithCompletion:^{
                                  [weakSelf createContents];

                                  [OWSAlerts
                                      showAlertWithTitle:NSLocalizedString(@"ALERT_ERROR_TITLE", @"")
                                                 message:NSLocalizedString(@"ENABLE_2FA_VIEW_COULD_NOT_DISABLE_2FA",
                                                             @"Error indicating that attempt to disable 'two-factor "
                                                             @"auth' failed.")];
                              }];
                          }];
                  }];
}

- (void)tryToEnable2FA
{
    OWSAssert(self.candidatePin.length > 0);

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    __weak OWS2FASettingsViewController *weakSelf = self;

    [ModalActivityIndicatorViewController
        presentFromViewController:self
                        canCancel:NO
                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                      [OWS2FAManager.sharedManager enable2FAWithPin:self.candidatePin
                          success:^{
                              [modalActivityIndicator dismissWithCompletion:^{
                                  [weakSelf showCompleteUI];
                              }];
                          }
                          failure:^(NSError *error) {
                              [modalActivityIndicator dismissWithCompletion:^{
                                  // The client may have fallen out of sync with the service.
                                  // Try to get back to a known good state by disabling 2FA
                                  // whenever enabling it fails.
                                  [OWS2FAManager.sharedManager disable2FAWithSuccess:nil failure:nil];

                                  [weakSelf updateTableContents];

                                  [OWSAlerts
                                      showAlertWithTitle:NSLocalizedString(@"ALERT_ERROR_TITLE", @"")
                                                 message:NSLocalizedString(@"ENABLE_2FA_VIEW_COULD_NOT_ENABLE_2FA",
                                                             @"Error indicating that attempt to enable 'two-factor "
                                                             @"auth' failed.")];
                              }];
                          }];
                  }];
}

- (void)showCompleteUI
{
    OWSAssert([OWS2FAManager.sharedManager is2FAEnabled]);
    OWSAssert(self.root2FAViewController);

    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [self.navigationController popToViewController:self.root2FAViewController animated:NO];
}

- (void)backButtonWasPressed
{
    [self.navigationController popViewControllerAnimated:YES];
}

@end

NS_ASSUME_NONNULL_END

//#import "RegistrationViewController.h"
//#import "CodeVerificationViewController.h"
//#import "CountryCodeViewController.h"
//#import "PhoneNumber.h"
//#import "PhoneNumberUtil.h"
//#import "Signal-Swift.h"
//#import "TSAccountManager.h"
//#import "UIView+OWS.h"
//#import "ViewControllerUtils.h"
//#import <SAMKeychain/SAMKeychain.h>
//#import <SignalMessaging/Environment.h>
//#import <SignalMessaging/NSString+OWS.h>
//
// NS_ASSUME_NONNULL_BEGIN
//
//#ifdef DEBUG
//
// NSString *const kKeychainService_LastRegistered = @"kKeychainService_LastRegistered";
// NSString *const kKeychainKey_LastRegisteredCountryCode = @"kKeychainKey_LastRegisteredCountryCode";
// NSString *const kKeychainKey_LastRegisteredPhoneNumber = @"kKeychainKey_LastRegisteredPhoneNumber";
//
//#endif
//
//@interface RegistrationViewController () <CountryCodeViewControllerDelegate, UITextFieldDelegate>
//
//@property (nonatomic) NSString *countryCode;
//@property (nonatomic) NSString *callingCode;
//
//@property (nonatomic) UILabel *countryCodeLabel;
//@property (nonatomic) UITextField *phoneNumberTextField;
//@property (nonatomic) UILabel *examplePhoneNumberLabel;
//@property (nonatomic) OWSFlatButton *activateButton;
//@property (nonatomic) UIActivityIndicatorView *spinnerView;
//
//@end
//
//#pragma mark -
//
//@implementation RegistrationViewController
//
//- (void)loadView
//{
//    [super loadView];
//
//    [self createViews];
//
//    // Do any additional setup after loading the view.
//    [self populateDefaultCountryNameAndCode];
//    [SignalApp.sharedApp setSignUpFlowNavigationController:self.navigationController];
//}
//
//- (void)viewDidLoad {
//    [super viewDidLoad];
//
//    OWSProdInfo([OWSAnalyticsEvents registrationBegan]);
//}
//
//- (void)createViews
//{
//    self.view.backgroundColor = [UIColor whiteColor];
//    self.view.userInteractionEnabled = YES;
//    [self.view
//     addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)]];
//
//    UIView *headerWrapper = [UIView containerView];
//    [self.view addSubview:headerWrapper];
//    headerWrapper.backgroundColor = UIColor.ows_signalBrandBlueColor;
//
//    UIView *headerContent = [UIView new];
//    [headerWrapper addSubview:headerContent];
//    [headerWrapper autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsZero excludingEdge:ALEdgeBottom];
//    [headerContent autoPinEdgeToSuperviewEdge:ALEdgeBottom];
//    [headerContent autoPinToTopLayoutGuideOfViewController:self withInset:0];
//    [headerContent autoPinWidthToSuperview];
//
//    UILabel *headerLabel = [UILabel new];
//    headerLabel.text = NSLocalizedString(@"REGISTRATION_TITLE_LABEL", @"");
//    headerLabel.textColor = [UIColor whiteColor];
//    headerLabel.font = [UIFont ows_mediumFontWithSize:ScaleFromIPhone5To7Plus(20.f, 24.f)];
//    [headerContent addSubview:headerLabel];
//    [headerLabel autoHCenterInSuperview];
//    [headerLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:14.f];
//
//    CGFloat screenHeight = MAX([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
//    if (screenHeight < 568) {
//        // iPhone 4s or smaller.
//        [headerContent autoSetDimension:ALDimensionHeight toSize:20];
//        headerLabel.hidden = YES;
//    } else if (screenHeight < 667) {
//        // iPhone 5 or smaller.
//        [headerContent autoSetDimension:ALDimensionHeight toSize:80];
//    } else {
//        [headerContent autoSetDimension:ALDimensionHeight toSize:220];
//
//        UIImage *logo = [UIImage imageNamed:@"logoSignal"];
//        OWSAssert(logo);
//        UIImageView *logoView = [UIImageView new];
//        logoView.image = logo;
//        [headerContent addSubview:logoView];
//        [logoView autoHCenterInSuperview];
//        [logoView autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:headerLabel withOffset:-14.f];
//    }
//
//    const CGFloat kRowHeight = 60.f;
//    const CGFloat kRowHMargin = 20.f;
//    const CGFloat kSeparatorHeight = 1.f;
//    const CGFloat kExamplePhoneNumberVSpacing = 8.f;
//    const CGFloat fontSizePoints = ScaleFromIPhone5To7Plus(16.f, 20.f);
//
//    UIView *contentView = [UIView containerView];
//    [contentView setHLayoutMargins:kRowHMargin];
//    contentView.backgroundColor = [UIColor whiteColor];
//    [self.view addSubview:contentView];
//    [contentView autoPinToBottomLayoutGuideOfViewController:self withInset:0];
//    [contentView autoPinWidthToSuperview];
//    [contentView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:headerContent];
//
//    // Country
//    UIView *countryRow = [UIView containerView];
//    [contentView addSubview:countryRow];
//    [countryRow autoPinLeadingAndTrailingToSuperview];
//    [countryRow autoPinEdgeToSuperviewEdge:ALEdgeTop];
//    [countryRow autoSetDimension:ALDimensionHeight toSize:kRowHeight];
//    [countryRow
//     addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
//                                                                  action:@selector(countryCodeRowWasTapped:)]];
//
//    UILabel *countryNameLabel = [UILabel new];
//    countryNameLabel.text
//    = NSLocalizedString(@"REGISTRATION_DEFAULT_COUNTRY_NAME", @"Label for the country code field");
//    countryNameLabel.textColor = [UIColor blackColor];
//    countryNameLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
//    [countryRow addSubview:countryNameLabel];
//    [countryNameLabel autoVCenterInSuperview];
//    [countryNameLabel autoPinLeadingToSuperview];
//
//    UILabel *countryCodeLabel = [UILabel new];
//    self.countryCodeLabel = countryCodeLabel;
//    countryCodeLabel.textColor = [UIColor ows_materialBlueColor];
//    countryCodeLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints + 2.f];
//    [countryRow addSubview:countryCodeLabel];
//    [countryCodeLabel autoVCenterInSuperview];
//    [countryCodeLabel autoPinTrailingToSuperview];
//
//    UIView *separatorView1 = [UIView new];
//    separatorView1.backgroundColor = [UIColor colorWithWhite:0.75f alpha:1.f];
//    [contentView addSubview:separatorView1];
//    [separatorView1 autoPinWidthToSuperview];
//    [separatorView1 autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:countryRow];
//    [separatorView1 autoSetDimension:ALDimensionHeight toSize:kSeparatorHeight];
//
//    // Phone Number
//    UIView *phoneNumberRow = [UIView containerView];
//    [contentView addSubview:phoneNumberRow];
//    [phoneNumberRow autoPinLeadingAndTrailingToSuperview];
//    [phoneNumberRow autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:separatorView1];
//    [phoneNumberRow autoSetDimension:ALDimensionHeight toSize:kRowHeight];
//
//    UILabel *phoneNumberLabel = [UILabel new];
//    phoneNumberLabel.text
//    = NSLocalizedString(@"REGISTRATION_PHONENUMBER_BUTTON", @"Label for the phone number textfield");
//    phoneNumberLabel.textColor = [UIColor blackColor];
//    phoneNumberLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
//    [phoneNumberRow addSubview:phoneNumberLabel];
//    [phoneNumberLabel autoVCenterInSuperview];
//    [phoneNumberLabel autoPinLeadingToSuperview];
//
//    UITextField *phoneNumberTextField = [UITextField new];
//    phoneNumberTextField.textAlignment = NSTextAlignmentRight;
//    phoneNumberTextField.delegate = self;
//    phoneNumberTextField.keyboardType = UIKeyboardTypeNumberPad;
//    phoneNumberTextField.placeholder = NSLocalizedString(
//                                                         @"REGISTRATION_ENTERNUMBER_DEFAULT_TEXT", @"Placeholder text
//                                                         for the phone number textfield");
//    self.phoneNumberTextField = phoneNumberTextField;
//    phoneNumberTextField.textColor = [UIColor ows_materialBlueColor];
//    phoneNumberTextField.font = [UIFont ows_mediumFontWithSize:fontSizePoints + 2];
//    [phoneNumberRow addSubview:phoneNumberTextField];
//    [phoneNumberTextField autoVCenterInSuperview];
//    [phoneNumberTextField autoPinTrailingToSuperview];
//
//    UILabel *examplePhoneNumberLabel = [UILabel new];
//    self.examplePhoneNumberLabel = examplePhoneNumberLabel;
//    examplePhoneNumberLabel.font = [UIFont ows_regularFontWithSize:fontSizePoints - 2.f];
//    examplePhoneNumberLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
//    [contentView addSubview:examplePhoneNumberLabel];
//    [examplePhoneNumberLabel autoPinTrailingToSuperview];
//    [examplePhoneNumberLabel autoPinEdge:ALEdgeTop
//                                  toEdge:ALEdgeBottom
//                                  ofView:phoneNumberTextField
//                              withOffset:kExamplePhoneNumberVSpacing];
//
//    UIView *separatorView2 = [UIView new];
//    separatorView2.backgroundColor = [UIColor colorWithWhite:0.75f alpha:1.f];
//    [contentView addSubview:separatorView2];
//    [separatorView2 autoPinWidthToSuperview];
//    [separatorView2 autoPinEdge:ALEdgeTop
//                         toEdge:ALEdgeBottom
//                         ofView:phoneNumberRow
//                     withOffset:examplePhoneNumberLabel.font.lineHeight];
//    [separatorView2 autoSetDimension:ALDimensionHeight toSize:kSeparatorHeight];
//
//    // Activate Button
//    const CGFloat kActivateButtonHeight = 47.f;
//    // NOTE: We use ows_signalBrandBlueColor instead of ows_materialBlueColor
//    //       throughout the onboarding flow to be consistent with the headers.
//    OWSFlatButton *activateButton = [OWSFlatButton buttonWithTitle:NSLocalizedString(@"REGISTRATION_VERIFY_DEVICE",
//    @"")
//                                                              font:[OWSFlatButton fontForHeight:kActivateButtonHeight]
//                                                        titleColor:[UIColor whiteColor]
//                                                   backgroundColor:[UIColor ows_signalBrandBlueColor]
//                                                            target:self
//                                                          selector:@selector(sendCodeAction)];
//    self.activateButton = activateButton;
//    [contentView addSubview:activateButton];
//    [activateButton autoPinLeadingAndTrailingToSuperview];
//    [activateButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:separatorView2 withOffset:15];
//    [activateButton autoSetDimension:ALDimensionHeight toSize:kActivateButtonHeight];
//
//    UIActivityIndicatorView *spinnerView =
//    [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
//    self.spinnerView = spinnerView;
//    [activateButton addSubview:spinnerView];
//    [spinnerView autoVCenterInSuperview];
//    [spinnerView autoSetDimension:ALDimensionWidth toSize:20.f];
//    [spinnerView autoSetDimension:ALDimensionHeight toSize:20.f];
//    [spinnerView autoPinTrailingToSuperviewWithMargin:20.f];
//    [spinnerView stopAnimating];
//}
//
//- (void)viewDidAppear:(BOOL)animated {
//    [super viewDidAppear:animated];
//
//    [self.activateButton setEnabled:YES];
//    [self.spinnerView stopAnimating];
//    [self.phoneNumberTextField becomeFirstResponder];
//}
//
//#pragma mark - Country
//
//- (void)populateDefaultCountryNameAndCode {
//    NSString *countryCode = [PhoneNumber defaultCountryCode];
//
//#ifdef DEBUG
//    if ([self lastRegisteredCountryCode].length > 0) {
//        countryCode = [self lastRegisteredCountryCode];
//    }
//    self.phoneNumberTextField.text = [self lastRegisteredPhoneNumber];
//#endif
//
//    NSNumber *callingCode = [[PhoneNumberUtil sharedUtil].nbPhoneNumberUtil getCountryCodeForRegion:countryCode];
//    NSString *countryName = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
//    [self updateCountryWithName:countryName
//                    callingCode:[NSString stringWithFormat:@"%@%@",
//                                 COUNTRY_CODE_PREFIX,
//                                 callingCode]
//                    countryCode:countryCode];
//}
//
//- (void)updateCountryWithName:(NSString *)countryName
//                  callingCode:(NSString *)callingCode
//                  countryCode:(NSString *)countryCode {
//    OWSAssertIsOnMainThread();
//    OWSAssert(countryName.length > 0);
//    OWSAssert(callingCode.length > 0);
//    OWSAssert(countryCode.length > 0);
//
//    _countryCode = countryCode;
//    _callingCode = callingCode;
//
//    NSString *title = [NSString stringWithFormat:@"%@ (%@)",
//                       callingCode,
//                       countryCode.uppercaseString];
//    self.countryCodeLabel.text = title;
//    [self.countryCodeLabel setNeedsLayout];
//
//    self.examplePhoneNumberLabel.text =
//    [ViewControllerUtils examplePhoneNumberForCountryCode:countryCode callingCode:callingCode];
//    [self.examplePhoneNumberLabel setNeedsLayout];
//}
//
//#pragma mark - Actions
//
//- (void)sendCodeAction
//{
//    NSString *phoneNumberText = [_phoneNumberTextField.text ows_stripped];
//    if (phoneNumberText.length < 1) {
//        [OWSAlerts
//         showAlertWithTitle:NSLocalizedString(@"REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_TITLE",
//                                              @"Title of alert indicating that users needs to enter a phone number to
//                                              register.")
//         message:
//         NSLocalizedString(@"REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_MESSAGE",
//                           @"Message of alert indicating that users needs to enter a phone number to register.")];
//        return;
//    }
//    NSString *countryCode = self.countryCode;
//    NSString *phoneNumber = [NSString stringWithFormat:@"%@%@", _callingCode, phoneNumberText];
//    PhoneNumber *localNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumber];
//    NSString *parsedPhoneNumber = localNumber.toE164;
//    if (parsedPhoneNumber.length < 1) {
//        [OWSAlerts showAlertWithTitle:
//         NSLocalizedString(@"REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_TITLE",
//                           @"Title of alert indicating that users needs to enter a valid phone number to register.")
//                              message:NSLocalizedString(@"REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_MESSAGE",
//                                                        @"Message of alert indicating that users needs to enter a
//                                                        valid phone number "
//                                                        @"to register.")];
//        return;
//    }
//
//    [self.activateButton setEnabled:NO];
//    [self.spinnerView startAnimating];
//    [self.phoneNumberTextField resignFirstResponder];
//
//    __weak RegistrationViewController *weakSelf = self;
//    [TSAccountManager registerWithPhoneNumber:parsedPhoneNumber
//                                      success:^{
//                                          OWSProdInfo([OWSAnalyticsEvents registrationRegisteredPhoneNumber]);
//
//                                          [weakSelf.spinnerView stopAnimating];
//
//                                          CodeVerificationViewController *vc = [CodeVerificationViewController new];
//                                          [weakSelf.navigationController pushViewController:vc animated:YES];
//
//#ifdef DEBUG
//                                          [weakSelf setLastRegisteredCountryCode:countryCode];
//                                          [weakSelf setLastRegisteredPhoneNumber:phoneNumberText];
//#endif
//                                      }
//                                      failure:^(NSError *error) {
//                                          if (error.code == 400) {
//                                              [OWSAlerts showAlertWithTitle:NSLocalizedString(@"REGISTRATION_ERROR",
//                                              nil)
//                                                                    message:NSLocalizedString(@"REGISTRATION_NON_VALID_NUMBER",
//                                                                    nil)];
//                                          } else {
//                                              [OWSAlerts showAlertWithTitle:error.localizedDescription
//                                              message:error.localizedRecoverySuggestion];
//                                          }
//
//                                          [weakSelf.activateButton setEnabled:YES];
//                                          [weakSelf.spinnerView stopAnimating];
//                                          [weakSelf.phoneNumberTextField becomeFirstResponder];
//                                      }
//                              smsVerification:YES];
//}
//
//- (void)countryCodeRowWasTapped:(UIGestureRecognizer *)sender
//{
//    if (sender.state == UIGestureRecognizerStateRecognized) {
//        [self changeCountryCodeTapped];
//    }
//}
//
//- (void)changeCountryCodeTapped
//{
//    CountryCodeViewController *countryCodeController = [CountryCodeViewController new];
//    countryCodeController.countryCodeDelegate = self;
//    UINavigationController *navigationController =
//    [[UINavigationController alloc] initWithRootViewController:countryCodeController];
//    [self presentViewController:navigationController animated:YES completion:[UIUtil modalCompletionBlock]];
//}
//
//- (void)backgroundTapped:(UIGestureRecognizer *)sender
//{
//    if (sender.state == UIGestureRecognizerStateRecognized) {
//        [self.phoneNumberTextField becomeFirstResponder];
//    }
//}
//
//#pragma mark - CountryCodeViewControllerDelegate
//
//- (void)countryCodeViewController:(CountryCodeViewController *)vc
//             didSelectCountryCode:(NSString *)countryCode
//                      countryName:(NSString *)countryName
//                      callingCode:(NSString *)callingCode
//{
//    OWSAssert(countryCode.length > 0);
//    OWSAssert(countryName.length > 0);
//    OWSAssert(callingCode.length > 0);
//
//    [self updateCountryWithName:countryName callingCode:callingCode countryCode:countryCode];
//
//    // Trigger the formatting logic with a no-op edit.
//    [self textField:self.phoneNumberTextField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@""];
//}
//
//#pragma mark - Keyboard notifications
//
//- (void)initializeKeyboardHandlers {
//    UITapGestureRecognizer *outsideTabRecognizer =
//    [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
//    [self.view addGestureRecognizer:outsideTabRecognizer];
//}
//
//- (void)dismissKeyboardFromAppropriateSubView {
//    [self.view endEditing:NO];
//}
//
//#pragma mark - UITextFieldDelegate
//
//- (BOOL)textField:(UITextField *)textField
// shouldChangeCharactersInRange:(NSRange)range
// replacementString:(NSString *)insertionText {
//
//    [ViewControllerUtils phoneNumberTextField:textField
//                shouldChangeCharactersInRange:range
//                            replacementString:insertionText
//                                  countryCode:_callingCode];
//
//    return NO; // inform our caller that we took care of performing the change
//}
//
//- (BOOL)textFieldShouldReturn:(UITextField *)textField {
//    [self sendCodeAction];
//    [textField resignFirstResponder];
//    return NO;
//}
//
//#pragma mark - Debug
//
//#ifdef DEBUG
//
//- (NSString *_Nullable)debugValueForKey:(NSString *)key
//{
//    OWSCAssert([NSThread isMainThread]);
//    OWSCAssert(key.length > 0);
//
//    NSError *error;
//    NSString *value = [SAMKeychain passwordForService:kKeychainService_LastRegistered account:key error:&error];
//    if (value && !error) {
//        return value;
//    }
//    return nil;
//}
//
//- (void)setDebugValue:(NSString *)value forKey:(NSString *)key
//{
//    OWSCAssert([NSThread isMainThread]);
//    OWSCAssert(key.length > 0);
//    OWSCAssert(value.length > 0);
//
//    NSError *error;
//    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly];
//    BOOL success = [SAMKeychain setPassword:value forService:kKeychainService_LastRegistered account:key
//    error:&error]; if (!success || error) {
//        DDLogError(@"%@ Error persisting 'last registered' value in keychain: %@", self.logTag, error);
//    }
//}
//
//- (NSString *_Nullable)lastRegisteredCountryCode
//{
//    return [self debugValueForKey:kKeychainKey_LastRegisteredCountryCode];
//}
//
//- (void)setLastRegisteredCountryCode:(NSString *)value
//{
//    [self setDebugValue:value forKey:kKeychainKey_LastRegisteredCountryCode];
//}
//
//- (NSString *_Nullable)lastRegisteredPhoneNumber
//{
//    return [self debugValueForKey:kKeychainKey_LastRegisteredPhoneNumber];
//}
//
//- (void)setLastRegisteredPhoneNumber:(NSString *)value
//{
//    [self setDebugValue:value forKey:kKeychainKey_LastRegisteredPhoneNumber];
//}
//
//#endif
//
//@end
//
// NS_ASSUME_NONNULL_END
