//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "RegistrationViewController.h"
#import "CodeVerificationViewController.h"
#import "CountryCodeViewController.h"
#import "Environment.h"
#import "PhoneNumber.h"
#import "PhoneNumberUtil.h"
#import "Signal-Swift.h"
#import "TSAccountManager.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <SAMKeychain/SAMKeychain.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef DEBUG

NSString *const kKeychainService_LastRegistered = @"kKeychainService_LastRegistered";
NSString *const kKeychainKey_LastRegisteredCountryCode = @"kKeychainKey_LastRegisteredCountryCode";
NSString *const kKeychainKey_LastRegisteredPhoneNumber = @"kKeychainKey_LastRegisteredPhoneNumber";

#endif

@interface RegistrationViewController () <CountryCodeViewControllerDelegate, UITextFieldDelegate>

@property (nonatomic) NSString *countryCode;
@property (nonatomic) NSString *callingCode;

@property (nonatomic) UILabel *countryCodeLabel;
@property (nonatomic) UITextField *phoneNumberTextField;
@property (nonatomic) UILabel *examplePhoneNumberLabel;
@property (nonatomic) UIButton *activateButton;
@property (nonatomic) UIActivityIndicatorView *spinnerView;

@end

#pragma mark -

@implementation RegistrationViewController

- (void)loadView
{
    [super loadView];

    [self createViews];

    // Do any additional setup after loading the view.
    [self populateDefaultCountryNameAndCode];
    [[Environment getCurrent] setSignUpFlowNavigationController:self.navigationController];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    OWSProdInfo([OWSAnalyticsEvents registrationBegan]);
}

- (void)createViews
{
    self.view.backgroundColor = [UIColor ows_signalBrandBlueColor];
    self.view.userInteractionEnabled = YES;
    [self.view
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)]];

    UIView *header = [UIView new];
    header.backgroundColor = [UIColor ows_signalBrandBlueColor];
    [self.view addSubview:header];
    [header autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [header autoPinWidthToSuperview];

    UILabel *headerLabel = [UILabel new];
    headerLabel.text = NSLocalizedString(@"REGISTRATION_TITLE_LABEL", @"");
    headerLabel.textColor = [UIColor whiteColor];
    headerLabel.font = [UIFont ows_mediumFontWithSize:ScaleFromIPhone5To7Plus(20.f, 24.f)];
    [header addSubview:headerLabel];
    [headerLabel autoHCenterInSuperview];
    [headerLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:14.f];

    CGFloat screenHeight = MAX([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
    if (screenHeight < 568) {
        // iPhone 4s or smaller.
        [header autoSetDimension:ALDimensionHeight toSize:20];
        headerLabel.hidden = YES;
    } else if (screenHeight < 667) {
        // iPhone 5 or smaller.
        [header autoSetDimension:ALDimensionHeight toSize:80];
    } else {
        [header autoSetDimension:ALDimensionHeight toSize:220];

        UIImage *logo = [UIImage imageNamed:@"logoSignal"];
        OWSAssert(logo);
        UIImageView *logoView = [UIImageView new];
        logoView.image = logo;
        [header addSubview:logoView];
        [logoView autoHCenterInSuperview];
        [logoView autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:headerLabel withOffset:-14.f];
    }

    const CGFloat kRowHeight = 60.f;
    const CGFloat kRowHMargin = 20.f;
    const CGFloat kSeparatorHeight = 1.f;
    const CGFloat kExamplePhoneNumberVSpacing = 8.f;
    const CGFloat fontSizePoints = ScaleFromIPhone5To7Plus(16.f, 20.f);

    UIView *contentView = [UIView containerView];
    [contentView setHLayoutMargins:kRowHMargin];
    contentView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:contentView];
    [contentView autoPinToBottomLayoutGuideOfViewController:self withInset:0];
    [contentView autoPinWidthToSuperview];
    [contentView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:header];

    // Country
    UIView *countryRow = [UIView containerView];
    countryRow.preservesSuperviewLayoutMargins = YES;
    [contentView addSubview:countryRow];
    [countryRow autoPinLeadingAndTrailingToSuperview];
    [countryRow autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [countryRow autoSetDimension:ALDimensionHeight toSize:kRowHeight];
    [countryRow
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(countryCodeRowWasTapped:)]];

    UILabel *countryNameLabel = [UILabel new];
    countryNameLabel.text
        = NSLocalizedString(@"REGISTRATION_DEFAULT_COUNTRY_NAME", @"Label for the country code field");
    countryNameLabel.textColor = [UIColor blackColor];
    countryNameLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
    [countryRow addSubview:countryNameLabel];
    [countryNameLabel autoVCenterInSuperview];
    [countryNameLabel autoPinLeadingToSuperView];

    UILabel *countryCodeLabel = [UILabel new];
    self.countryCodeLabel = countryCodeLabel;
    countryCodeLabel.textColor = [UIColor ows_materialBlueColor];
    countryCodeLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints + 2.f];
    [countryRow addSubview:countryCodeLabel];
    [countryCodeLabel autoVCenterInSuperview];
    [countryCodeLabel autoPinTrailingToSuperView];

    UIView *separatorView1 = [UIView new];
    separatorView1.backgroundColor = [UIColor colorWithWhite:0.75f alpha:1.f];
    [contentView addSubview:separatorView1];
    [separatorView1 autoPinWidthToSuperview];
    [separatorView1 autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:countryRow];
    [separatorView1 autoSetDimension:ALDimensionHeight toSize:kSeparatorHeight];

    // Phone Number
    UIView *phoneNumberRow = [UIView containerView];
    phoneNumberRow.preservesSuperviewLayoutMargins = YES;
    [contentView addSubview:phoneNumberRow];
    [phoneNumberRow autoPinLeadingAndTrailingToSuperview];
    [phoneNumberRow autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:separatorView1];
    [phoneNumberRow autoSetDimension:ALDimensionHeight toSize:kRowHeight];

    UILabel *phoneNumberLabel = [UILabel new];
    phoneNumberLabel.text
        = NSLocalizedString(@"REGISTRATION_PHONENUMBER_BUTTON", @"Label for the phone number textfield");
    phoneNumberLabel.textColor = [UIColor blackColor];
    phoneNumberLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
    [phoneNumberRow addSubview:phoneNumberLabel];
    [phoneNumberLabel autoVCenterInSuperview];
    [phoneNumberLabel autoPinLeadingToSuperView];

    UITextField *phoneNumberTextField = [UITextField new];
    phoneNumberTextField.textAlignment = NSTextAlignmentRight;
    phoneNumberTextField.delegate = self;
    phoneNumberTextField.keyboardType = UIKeyboardTypeNumberPad;
    phoneNumberTextField.placeholder = NSLocalizedString(
        @"REGISTRATION_ENTERNUMBER_DEFAULT_TEXT", @"Placeholder text for the phone number textfield");
    self.phoneNumberTextField = phoneNumberTextField;
    phoneNumberTextField.textColor = [UIColor ows_materialBlueColor];
    phoneNumberTextField.font = [UIFont ows_mediumFontWithSize:fontSizePoints + 2];
    [phoneNumberRow addSubview:phoneNumberTextField];
    [phoneNumberTextField autoVCenterInSuperview];
    [phoneNumberTextField autoPinTrailingToSuperView];

    UILabel *examplePhoneNumberLabel = [UILabel new];
    self.examplePhoneNumberLabel = examplePhoneNumberLabel;
    examplePhoneNumberLabel.font = [UIFont ows_regularFontWithSize:fontSizePoints - 2.f];
    examplePhoneNumberLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
    [contentView addSubview:examplePhoneNumberLabel];
    [examplePhoneNumberLabel autoPinTrailingToSuperView];
    [examplePhoneNumberLabel autoPinEdge:ALEdgeTop
                                  toEdge:ALEdgeBottom
                                  ofView:phoneNumberTextField
                              withOffset:kExamplePhoneNumberVSpacing];

    UIView *separatorView2 = [UIView new];
    separatorView2.backgroundColor = [UIColor colorWithWhite:0.75f alpha:1.f];
    [contentView addSubview:separatorView2];
    [separatorView2 autoPinWidthToSuperview];
    [separatorView2 autoPinEdge:ALEdgeTop
                         toEdge:ALEdgeBottom
                         ofView:phoneNumberRow
                     withOffset:examplePhoneNumberLabel.font.lineHeight];
    [separatorView2 autoSetDimension:ALDimensionHeight toSize:kSeparatorHeight];

    // Activate Button
    UIButton *activateButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.activateButton = activateButton;
    activateButton.backgroundColor = [UIColor ows_signalBrandBlueColor];
    [activateButton setTitle:NSLocalizedString(@"REGISTRATION_VERIFY_DEVICE", @"") forState:UIControlStateNormal];
    [activateButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    activateButton.titleLabel.font = [UIFont ows_boldFontWithSize:fontSizePoints];
    [activateButton setContentHorizontalAlignment:UIControlContentHorizontalAlignmentCenter];
    [activateButton setContentVerticalAlignment:UIControlContentVerticalAlignmentCenter];
    [contentView addSubview:activateButton];
    [activateButton autoPinLeadingAndTrailingToSuperview];
    [activateButton autoPinEdge:ALEdgeTop
                         toEdge:ALEdgeBottom
                         ofView:separatorView2
                     withOffset:ScaleFromIPhone5To7Plus(12.f, 15.f)];
    [activateButton autoSetDimension:ALDimensionHeight toSize:47.f];
    [activateButton addTarget:self action:@selector(sendCodeAction) forControlEvents:UIControlEventTouchUpInside];

    UIActivityIndicatorView *spinnerView =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinnerView = spinnerView;
    [activateButton addSubview:spinnerView];
    [spinnerView autoVCenterInSuperview];
    [spinnerView autoSetDimension:ALDimensionWidth toSize:20.f];
    [spinnerView autoSetDimension:ALDimensionHeight toSize:20.f];
    [spinnerView autoPinTrailingToSuperViewWithMargin:20.f];
    [spinnerView stopAnimating];

    // Existing Account Button
    UIButton *existingAccountButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [existingAccountButton setTitle:NSLocalizedString(@"ALREADY_HAVE_ACCOUNT_BUTTON", @"registration button text")
                           forState:UIControlStateNormal];
    [existingAccountButton setTitleColor:[UIColor ows_materialBlueColor] forState:UIControlStateNormal];
    existingAccountButton.titleLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints - 2.f];
    [existingAccountButton setContentHorizontalAlignment:UIControlContentHorizontalAlignmentCenter];
    [existingAccountButton setContentVerticalAlignment:UIControlContentVerticalAlignmentCenter];
    [contentView addSubview:existingAccountButton];
    [existingAccountButton autoPinLeadingAndTrailingToSuperview];
    [existingAccountButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:activateButton withOffset:9.f];
    [existingAccountButton autoSetDimension:ALDimensionHeight toSize:36.f];
    [existingAccountButton addTarget:self
                              action:@selector(didTapExistingUserButton:)
                    forControlEvents:UIControlEventTouchUpInside];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [self.activateButton setEnabled:YES];
    [self.spinnerView stopAnimating];
    [self.phoneNumberTextField becomeFirstResponder];
}

#pragma mark - Country

- (void)populateDefaultCountryNameAndCode {
    NSLocale *locale      = NSLocale.currentLocale;
    NSString *countryCode = [locale objectForKey:NSLocaleCountryCode];

#ifdef DEBUG
    if ([self lastRegisteredCountryCode].length > 0) {
        countryCode = [self lastRegisteredCountryCode];
    }
    self.phoneNumberTextField.text = [self lastRegisteredPhoneNumber];
#endif

    NSNumber *callingCode = [[PhoneNumberUtil sharedUtil].nbPhoneNumberUtil getCountryCodeForRegion:countryCode];
    NSString *countryName = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
    [self updateCountryWithName:countryName
                    callingCode:[NSString stringWithFormat:@"%@%@",
                                 COUNTRY_CODE_PREFIX,
                                 callingCode]
                    countryCode:countryCode];
}

- (void)updateCountryWithName:(NSString *)countryName
                  callingCode:(NSString *)callingCode
                  countryCode:(NSString *)countryCode {
    OWSAssert([NSThread isMainThread]);
    OWSAssert(countryName.length > 0);
    OWSAssert(callingCode.length > 0);
    OWSAssert(countryCode.length > 0);

    _countryCode = countryCode;
    _callingCode = callingCode;

    NSString *title = [NSString stringWithFormat:@"%@ (%@)",
                       callingCode,
                       countryCode.uppercaseString];
    self.countryCodeLabel.text = title;
    [self.countryCodeLabel setNeedsLayout];

    self.examplePhoneNumberLabel.text =
        [ViewControllerUtils examplePhoneNumberForCountryCode:countryCode callingCode:callingCode];
    [self.examplePhoneNumberLabel setNeedsLayout];
}

#pragma mark - Actions

- (void)didTapExistingUserButton:(id)sender
{
    DDLogInfo(@"called %s", __PRETTY_FUNCTION__);

    [OWSAlerts
        showAlertWithTitle:
            [NSString stringWithFormat:NSLocalizedString(@"EXISTING_USER_REGISTRATION_ALERT_TITLE",
                                           @"during registration, embeds {{device type}}, e.g. \"iPhone\" or \"iPad\""),
                      [UIDevice currentDevice].localizedModel]
                   message:NSLocalizedString(@"EXISTING_USER_REGISTRATION_ALERT_BODY", @"during registration")];
}

- (void)sendCodeAction
{
    NSString *phoneNumberText =
        [_phoneNumberTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (phoneNumberText.length < 1) {
        [OWSAlerts
            showAlertWithTitle:NSLocalizedString(@"REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_TITLE",
                                   @"Title of alert indicating that users needs to enter a phone number to register.")
                       message:
                           NSLocalizedString(@"REGISTRATION_VIEW_NO_PHONE_NUMBER_ALERT_MESSAGE",
                               @"Message of alert indicating that users needs to enter a phone number to register.")];
        return;
    }
    NSString *countryCode = self.countryCode;
    NSString *phoneNumber = [NSString stringWithFormat:@"%@%@", _callingCode, phoneNumberText];
    PhoneNumber *localNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumber];
    NSString *parsedPhoneNumber = localNumber.toE164;
    if (parsedPhoneNumber.length < 1) {
        [OWSAlerts showAlertWithTitle:
                       NSLocalizedString(@"REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_TITLE",
                           @"Title of alert indicating that users needs to enter a valid phone number to register.")
                              message:NSLocalizedString(@"REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_MESSAGE",
                                          @"Message of alert indicating that users needs to enter a valid phone number "
                                          @"to register.")];
        return;
    }

    [self.activateButton setEnabled:NO];
    [self.spinnerView startAnimating];
    [self.phoneNumberTextField resignFirstResponder];

    __weak RegistrationViewController *weakSelf = self;
    [TSAccountManager registerWithPhoneNumber:parsedPhoneNumber
        success:^{
            OWSProdInfo([OWSAnalyticsEvents registrationRegisteredPhoneNumber]);

            [weakSelf.spinnerView stopAnimating];

            CodeVerificationViewController *vc = [CodeVerificationViewController new];
            [weakSelf.navigationController pushViewController:vc animated:YES];

#ifdef DEBUG
            [weakSelf setLastRegisteredCountryCode:countryCode];
            [weakSelf setLastRegisteredPhoneNumber:phoneNumberText];
#endif
        }
        failure:^(NSError *error) {
            if (error.code == 400) {
                [OWSAlerts showAlertWithTitle:NSLocalizedString(@"REGISTRATION_ERROR", nil)
                                      message:NSLocalizedString(@"REGISTRATION_NON_VALID_NUMBER", nil)];
            } else {
                [OWSAlerts showAlertWithTitle:error.localizedDescription message:error.localizedRecoverySuggestion];
            }

            [weakSelf.activateButton setEnabled:YES];
            [weakSelf.spinnerView stopAnimating];
            [weakSelf.phoneNumberTextField becomeFirstResponder];
        }
        smsVerification:YES];
}

- (void)countryCodeRowWasTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self changeCountryCodeTapped];
    }
}

- (void)changeCountryCodeTapped
{
    CountryCodeViewController *countryCodeController = [CountryCodeViewController new];
    countryCodeController.countryCodeDelegate = self;
    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:countryCodeController];
    [self presentViewController:navigationController animated:YES completion:[UIUtil modalCompletionBlock]];
}

- (void)presentInvalidCountryCodeError {
    [OWSAlerts showAlertWithTitle:NSLocalizedString(@"REGISTER_CC_ERR_ALERT_VIEW_TITLE", @"")
                          message:NSLocalizedString(@"REGISTER_CC_ERR_ALERT_VIEW_MESSAGE", @"")
                      buttonTitle:CommonStrings.dismissButton];
}

- (void)backgroundTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self.phoneNumberTextField becomeFirstResponder];
    }
}

#pragma mark - CountryCodeViewControllerDelegate

- (void)countryCodeViewController:(CountryCodeViewController *)vc
             didSelectCountryCode:(NSString *)countryCode
                      countryName:(NSString *)countryName
                      callingCode:(NSString *)callingCode
{
    OWSAssert(countryCode.length > 0);
    OWSAssert(countryName.length > 0);
    OWSAssert(callingCode.length > 0);

    [self updateCountryWithName:countryName callingCode:callingCode countryCode:countryCode];

    // Trigger the formatting logic with a no-op edit.
    [self textField:self.phoneNumberTextField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@""];
}

#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers {
    UITapGestureRecognizer *outsideTabRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.view addGestureRecognizer:outsideTabRecognizer];
}

- (void)dismissKeyboardFromAppropriateSubView {
    [self.view endEditing:NO];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText {

    [ViewControllerUtils phoneNumberTextField:textField
                shouldChangeCharactersInRange:range
                            replacementString:insertionText
                                  countryCode:_callingCode];

    return NO; // inform our caller that we took care of performing the change
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendCodeAction];
    [textField resignFirstResponder];
    return NO;
}

#pragma mark - Debug

#ifdef DEBUG

- (NSString *_Nullable)debugValueForKey:(NSString *)key
{
    OWSCAssert([NSThread isMainThread]);
    OWSCAssert(key.length > 0);

    NSError *error;
    NSString *value = [SAMKeychain passwordForService:kKeychainService_LastRegistered account:key error:&error];
    if (value && !error) {
        return value;
    }
    return nil;
}

- (void)setDebugValue:(NSString *)value forKey:(NSString *)key
{
    OWSCAssert([NSThread isMainThread]);
    OWSCAssert(key.length > 0);
    OWSCAssert(value.length > 0);

    NSError *error;
    [SAMKeychain setPassword:value forService:kKeychainService_LastRegistered account:key error:&error];
    if (error) {
        DDLogError(@"%@ Error persisting 'last registered' value in keychain: %@", self.tag, error);
    }
}

- (NSString *_Nullable)lastRegisteredCountryCode
{
    return [self debugValueForKey:kKeychainKey_LastRegisteredCountryCode];
}

- (void)setLastRegisteredCountryCode:(NSString *)value
{
    [self setDebugValue:value forKey:kKeychainKey_LastRegisteredCountryCode];
}

- (NSString *_Nullable)lastRegisteredPhoneNumber
{
    return [self debugValueForKey:kKeychainKey_LastRegisteredPhoneNumber];
}

- (void)setLastRegisteredPhoneNumber:(NSString *)value
{
    [self setDebugValue:value forKey:kKeychainKey_LastRegisteredPhoneNumber];
}

#endif

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
