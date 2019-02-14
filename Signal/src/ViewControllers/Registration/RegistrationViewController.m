//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "RegistrationViewController.h"
#import "CodeVerificationViewController.h"
#import "CountryCodeViewController.h"
#import "PhoneNumber.h"
#import "PhoneNumberUtil.h"
#import "Signal-Swift.h"
#import "TSAccountManager.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSNavigationController.h>
#import <SignalServiceKit/NSString+SSK.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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
@property (nonatomic) OWSFlatButton *activateButton;
@property (nonatomic) UIActivityIndicatorView *spinnerView;

@end

#pragma mark -

@implementation RegistrationViewController

#pragma mark - Dependencies

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);
    
    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark -

- (void)loadView
{
    [super loadView];

    self.shouldUseTheme = NO;

    [self createViews];

    // Do any additional setup after loading the view.
    [self populateDefaultCountryNameAndCode];
    OWSAssertDebug([self.navigationController isKindOfClass:[OWSNavigationController class]]);
    [SignalApp.sharedApp setSignUpFlowNavigationController:(OWSNavigationController *)self.navigationController];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    OWSProdInfo([OWSAnalyticsEvents registrationBegan]);
}

- (void)createViews
{
    self.view.backgroundColor = [UIColor whiteColor];
    self.view.userInteractionEnabled = YES;
    [self.view
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)]];

    UIView *headerWrapper = [UIView containerView];
    [self.view addSubview:headerWrapper];
    headerWrapper.backgroundColor = UIColor.ows_signalBrandBlueColor;
    [headerWrapper autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsZero excludingEdge:ALEdgeBottom];

    UILabel *headerLabel = [UILabel new];
    headerLabel.text = NSLocalizedString(@"REGISTRATION_TITLE_LABEL", @"");
    headerLabel.textColor = [UIColor whiteColor];
    headerLabel.font = [UIFont ows_mediumFontWithSize:ScaleFromIPhone5To7Plus(20.f, 24.f)];

    NSString *legalTopMatterFormat = NSLocalizedString(@"REGISTRATION_LEGAL_TOP_MATTER_FORMAT",
        @"legal disclaimer, embeds a tappable {{link title}} which is styled as a hyperlink");
    NSString *legalTopMatterLinkWord = NSLocalizedString(
        @"REGISTRATION_LEGAL_TOP_MATTER_LINK_TITLE", @"embedded in legal topmatter, styled as a link");
    NSString *legalTopMatter = [NSString stringWithFormat:legalTopMatterFormat, legalTopMatterLinkWord];
    NSMutableAttributedString *attributedLegalTopMatter =
        [[NSMutableAttributedString alloc] initWithString:legalTopMatter];
    NSRange linkRange = [legalTopMatter rangeOfString:legalTopMatterLinkWord];
    NSDictionary *linkStyleAttributes = @{
        NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid),
    };
    [attributedLegalTopMatter setAttributes:linkStyleAttributes range:linkRange];

    UILabel *legalTopMatterLabel = [UILabel new];
    legalTopMatterLabel.textColor = UIColor.whiteColor;
    legalTopMatterLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(13.f, 15.f)];
    legalTopMatterLabel.numberOfLines = 0;
    legalTopMatterLabel.textAlignment = NSTextAlignmentCenter;
    legalTopMatterLabel.attributedText = attributedLegalTopMatter;
    legalTopMatterLabel.userInteractionEnabled = YES;

    UITapGestureRecognizer *tapGesture =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTapLegalTerms:)];
    [legalTopMatterLabel addGestureRecognizer:tapGesture];

    UIStackView *headerContent = [[UIStackView alloc] initWithArrangedSubviews:@[ headerLabel ]];
    [headerContent addArrangedSubview:legalTopMatterLabel];
    headerContent.axis = UILayoutConstraintAxisVertical;
    headerContent.alignment = UIStackViewAlignmentCenter;
    headerContent.spacing = ScaleFromIPhone5To7Plus(8, 16);
    headerContent.layoutMarginsRelativeArrangement = YES;

    {
        CGFloat topMargin = ScaleFromIPhone5To7Plus(4, 16);
        CGFloat bottomMargin = ScaleFromIPhone5To7Plus(8, 16);
        headerContent.layoutMargins = UIEdgeInsetsMake(topMargin, 40, bottomMargin, 40);
    }

    [headerWrapper addSubview:headerContent];
    [headerContent autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [headerContent autoPinEdgesToSuperviewMarginsExcludingEdge:ALEdgeTop];

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
    [contentView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:headerContent];

    // Country
    UIView *countryRow = [UIView containerView];
    [contentView addSubview:countryRow];
    [countryRow autoPinLeadingAndTrailingToSuperviewMargin];
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
    [countryNameLabel autoPinLeadingToSuperviewMargin];

    UILabel *countryCodeLabel = [UILabel new];
    self.countryCodeLabel = countryCodeLabel;
    countryCodeLabel.textColor = [UIColor ows_materialBlueColor];
    countryCodeLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints + 2.f];
    [countryRow addSubview:countryCodeLabel];
    [countryCodeLabel autoVCenterInSuperview];
    [countryCodeLabel autoPinTrailingToSuperviewMargin];

    UIView *separatorView1 = [UIView new];
    separatorView1.backgroundColor = [UIColor colorWithWhite:0.75f alpha:1.f];
    [contentView addSubview:separatorView1];
    [separatorView1 autoPinWidthToSuperview];
    [separatorView1 autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:countryRow];
    [separatorView1 autoSetDimension:ALDimensionHeight toSize:kSeparatorHeight];

    // Phone Number
    UIView *phoneNumberRow = [UIView containerView];
    [contentView addSubview:phoneNumberRow];
    [phoneNumberRow autoPinLeadingAndTrailingToSuperviewMargin];
    [phoneNumberRow autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:separatorView1];
    [phoneNumberRow autoSetDimension:ALDimensionHeight toSize:kRowHeight];

    UILabel *phoneNumberLabel = [UILabel new];
    phoneNumberLabel.text
        = NSLocalizedString(@"REGISTRATION_PHONENUMBER_BUTTON", @"Label for the phone number textfield");
    phoneNumberLabel.textColor = [UIColor blackColor];
    phoneNumberLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
    [phoneNumberRow addSubview:phoneNumberLabel];
    [phoneNumberLabel autoVCenterInSuperview];
    [phoneNumberLabel autoPinLeadingToSuperviewMargin];

    UITextField *phoneNumberTextField;
    if (UIDevice.currentDevice.isShorterThanIPhone5) {
        phoneNumberTextField = [DismissableTextField new];
    } else {
        phoneNumberTextField = [OWSTextField new];
    }

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
    [phoneNumberTextField autoPinTrailingToSuperviewMargin];

    UILabel *examplePhoneNumberLabel = [UILabel new];
    self.examplePhoneNumberLabel = examplePhoneNumberLabel;
    examplePhoneNumberLabel.font = [UIFont ows_regularFontWithSize:fontSizePoints - 2.f];
    examplePhoneNumberLabel.textColor = Theme.middleGrayColor;
    [contentView addSubview:examplePhoneNumberLabel];
    [examplePhoneNumberLabel autoPinTrailingToSuperviewMargin];
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
    const CGFloat kActivateButtonHeight = 47.f;
    // NOTE: We use ows_signalBrandBlueColor instead of ows_materialBlueColor
    //       throughout the onboarding flow to be consistent with the headers.
    OWSFlatButton *activateButton = [OWSFlatButton buttonWithTitle:NSLocalizedString(@"REGISTRATION_VERIFY_DEVICE", @"")
                                                              font:[OWSFlatButton fontForHeight:kActivateButtonHeight]
                                                        titleColor:[UIColor whiteColor]
                                                   backgroundColor:[UIColor ows_signalBrandBlueColor]
                                                            target:self
                                                          selector:@selector(didTapRegisterButton)];
    self.activateButton = activateButton;
    [contentView addSubview:activateButton];
    [activateButton autoPinLeadingAndTrailingToSuperviewMargin];
    [activateButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:separatorView2 withOffset:15];
    [activateButton autoSetDimension:ALDimensionHeight toSize:kActivateButtonHeight];

    UIActivityIndicatorView *spinnerView =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinnerView = spinnerView;
    [activateButton addSubview:spinnerView];
    [spinnerView autoVCenterInSuperview];
    [spinnerView autoSetDimension:ALDimensionWidth toSize:20.f];
    [spinnerView autoSetDimension:ALDimensionHeight toSize:20.f];
    [spinnerView autoPinTrailingToSuperviewMarginWithInset:20.f];
    [spinnerView stopAnimating];

    NSString *bottomTermsLinkText = NSLocalizedString(@"REGISTRATION_LEGAL_TERMS_LINK",
        @"one line label below submit button on registration screen, which links to an external webpage.");
    UIButton *bottomLegalLinkButton = [UIButton new];
    bottomLegalLinkButton.titleLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(13.f, 15.f)];
    [bottomLegalLinkButton setTitleColor:UIColor.ows_materialBlueColor forState:UIControlStateNormal];
    [bottomLegalLinkButton setTitle:bottomTermsLinkText forState:UIControlStateNormal];
    [contentView addSubview:bottomLegalLinkButton];
    [bottomLegalLinkButton addTarget:self
                              action:@selector(didTapLegalTerms:)
                    forControlEvents:UIControlEventTouchUpInside];

    [bottomLegalLinkButton autoPinLeadingAndTrailingToSuperviewMargin];
    [bottomLegalLinkButton autoPinEdge:ALEdgeTop
                                toEdge:ALEdgeBottom
                                ofView:activateButton
                            withOffset:ScaleFromIPhone5To7Plus(8, 12)];
    [bottomLegalLinkButton setCompressionResistanceHigh];
    [bottomLegalLinkButton setContentHuggingHigh];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self.activateButton setEnabled:YES];
    [self.spinnerView stopAnimating];
    [self.phoneNumberTextField becomeFirstResponder];

    if (self.tsAccountManager.isReregistering) {
        // If re-registering, pre-populate the country (country code, calling code, country name)
        // and phone number state.
        NSString *_Nullable phoneNumberE164 = self.tsAccountManager.reregisterationPhoneNumber;
        if (!phoneNumberE164) {
            OWSFailDebug(@"Could not resume re-registration; missing phone number.");
        } else if ([self tryToApplyPhoneNumberE164:phoneNumberE164]) {
            // Don't let user edit their phone number while re-registering.
            self.phoneNumberTextField.enabled = NO;
        }
    }
}

- (BOOL)tryToApplyPhoneNumberE164:(NSString *)phoneNumberE164
{
    OWSAssertDebug(phoneNumberE164);

    if (phoneNumberE164.length < 1) {
        OWSFailDebug(@"Could not resume re-registration; invalid phoneNumberE164.");
        return NO;
    }
    PhoneNumber *_Nullable parsedPhoneNumber = [PhoneNumber phoneNumberFromE164:phoneNumberE164];
    if (!parsedPhoneNumber) {
        OWSFailDebug(@"Could not resume re-registration; couldn't parse phoneNumberE164.");
        return NO;
    }
    NSNumber *_Nullable callingCode = parsedPhoneNumber.getCountryCode;
    if (!callingCode) {
        OWSFailDebug(@"Could not resume re-registration; missing callingCode.");
        return NO;
    }
    NSString *callingCodeText = [NSString stringWithFormat:@"+%d", callingCode.intValue];
    NSArray<NSString *> *_Nullable countryCodes =
        [PhoneNumberUtil.sharedThreadLocal countryCodesFromCallingCode:callingCodeText];
    if (countryCodes.count < 1) {
        OWSFailDebug(@"Could not resume re-registration; unknown countryCode.");
        return NO;
    }
    NSString *countryCode = countryCodes.firstObject;
    NSString *_Nullable countryName = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
    if (!countryName) {
        OWSFailDebug(@"Could not resume re-registration; unknown countryName.");
        return NO;
    }
    if (![phoneNumberE164 hasPrefix:callingCodeText]) {
        OWSFailDebug(@"Could not resume re-registration; non-matching calling code.");
        return NO;
    }
    NSString *phoneNumberWithoutCallingCode = [phoneNumberE164 substringFromIndex:callingCodeText.length];

    [self updateCountryWithName:countryName callingCode:callingCodeText countryCode:countryCode];
    self.phoneNumberTextField.text = phoneNumberWithoutCallingCode;

    return YES;
}

#pragma mark - Country

- (void)populateDefaultCountryNameAndCode
{
    NSString *countryCode = [PhoneNumber defaultCountryCode];

#ifdef DEBUG
    if ([self lastRegisteredCountryCode].length > 0) {
        countryCode = [self lastRegisteredCountryCode];
    }
    self.phoneNumberTextField.text = [self lastRegisteredPhoneNumber];
#endif

    NSNumber *callingCode = [[PhoneNumberUtil sharedThreadLocal].nbPhoneNumberUtil getCountryCodeForRegion:countryCode];
    NSString *countryName = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
    [self updateCountryWithName:countryName
                    callingCode:[NSString stringWithFormat:@"%@%@", COUNTRY_CODE_PREFIX, callingCode]
                    countryCode:countryCode];
}

- (void)updateCountryWithName:(NSString *)countryName
                  callingCode:(NSString *)callingCode
                  countryCode:(NSString *)countryCode
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(countryName.length > 0);
    OWSAssertDebug(callingCode.length > 0);
    OWSAssertDebug(countryCode.length > 0);

    _countryCode = countryCode;
    _callingCode = callingCode;

    NSString *title = [NSString stringWithFormat:@"%@ (%@)", callingCode, countryCode.localizedUppercaseString];
    self.countryCodeLabel.text = title;
    [self.countryCodeLabel setNeedsLayout];

    self.examplePhoneNumberLabel.text =
        [ViewControllerUtils examplePhoneNumberForCountryCode:countryCode callingCode:callingCode];
    [self.examplePhoneNumberLabel setNeedsLayout];
}

#pragma mark - Actions

- (void)didTapRegisterButton
{
    NSString *phoneNumberText = [_phoneNumberTextField.text ows_stripped];
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
    if (parsedPhoneNumber.length < 1
        || ![[PhoneNumberValidator new] isValidForRegistrationWithPhoneNumber:localNumber]) {
        [OWSAlerts showAlertWithTitle:
                       NSLocalizedString(@"REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_TITLE",
                           @"Title of alert indicating that users needs to enter a valid phone number to register.")
                              message:NSLocalizedString(@"REGISTRATION_VIEW_INVALID_PHONE_NUMBER_ALERT_MESSAGE",
                                          @"Message of alert indicating that users needs to enter a valid phone number "
                                          @"to register.")];
        return;
    }

    if (UIDevice.currentDevice.isIPad) {
        [OWSAlerts showConfirmationAlertWithTitle:NSLocalizedString(@"REGISTRATION_IPAD_CONFIRM_TITLE",
                                                      @"alert title when registering an iPad")
                                          message:NSLocalizedString(@"REGISTRATION_IPAD_CONFIRM_BODY",
                                                      @"alert body when registering an iPad")
                                     proceedTitle:NSLocalizedString(@"REGISTRATION_IPAD_CONFIRM_BUTTON",
                                                      @"button text to proceed with registration when on an iPad")
                                    proceedAction:^(UIAlertAction *_Nonnull action) {
                                        [self sendCodeActionWithParsedPhoneNumber:parsedPhoneNumber
                                                                  phoneNumberText:phoneNumberText
                                                                      countryCode:countryCode];
                                    }];
    } else {
        [self sendCodeActionWithParsedPhoneNumber:parsedPhoneNumber
                                  phoneNumberText:phoneNumberText
                                      countryCode:countryCode];
    }
}

- (void)sendCodeActionWithParsedPhoneNumber:(NSString *)parsedPhoneNumber
                            phoneNumberText:(NSString *)phoneNumberText
                                countryCode:(NSString *)countryCode
{
    [self.activateButton setEnabled:NO];
    [self.spinnerView startAnimating];
    [self.phoneNumberTextField resignFirstResponder];

    __weak RegistrationViewController *weakSelf = self;
    [self.tsAccountManager registerWithPhoneNumber:parsedPhoneNumber
        captchaToken:nil
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
    if (self.tsAccountManager.isReregistering) {
        // Don't let user edit their phone number while re-registering.
        return;
    }

    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self changeCountryCodeTapped];
    }
}

- (void)didTapLegalTerms:(UIButton *)sender
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:kLegalTermsUrlString]];
}

- (void)changeCountryCodeTapped
{
    CountryCodeViewController *countryCodeController = [CountryCodeViewController new];
    countryCodeController.countryCodeDelegate = self;
    countryCodeController.interfaceOrientationMask = UIInterfaceOrientationMaskPortrait;
    OWSNavigationController *navigationController =
        [[OWSNavigationController alloc] initWithRootViewController:countryCodeController];
    [self presentViewController:navigationController animated:YES completion:nil];
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
    OWSAssertDebug(countryCode.length > 0);
    OWSAssertDebug(countryName.length > 0);
    OWSAssertDebug(callingCode.length > 0);

    [self updateCountryWithName:countryName callingCode:callingCode countryCode:countryCode];

    // Trigger the formatting logic with a no-op edit.
    [self textField:self.phoneNumberTextField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@""];
}

#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers
{
    UITapGestureRecognizer *outsideTabRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.view addGestureRecognizer:outsideTabRecognizer];
}

- (void)dismissKeyboardFromAppropriateSubView
{
    [self.view endEditing:NO];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
{

    [ViewControllerUtils phoneNumberTextField:textField
                shouldChangeCharactersInRange:range
                            replacementString:insertionText
                                  countryCode:_callingCode];

    return NO; // inform our caller that we took care of performing the change
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self didTapRegisterButton];
    [textField resignFirstResponder];
    return NO;
}

#pragma mark - Debug

#ifdef DEBUG

- (NSString *_Nullable)debugValueForKey:(NSString *)key
{
    OWSCAssertDebug([NSThread isMainThread]);
    OWSCAssertDebug(key.length > 0);

    NSError *error;
    NSString *_Nullable value =
        [CurrentAppContext().keychainStorage stringForService:kKeychainService_LastRegistered key:key error:&error];
    if (error || !value) {
        OWSLogWarn(@"Could not retrieve 'last registered' value from keychain: %@.", error);
        return nil;
    }
    return value;
}

- (void)setDebugValue:(NSString *)value forKey:(NSString *)key
{
    OWSCAssertDebug([NSThread isMainThread]);
    OWSCAssertDebug(key.length > 0);
    OWSCAssertDebug(value.length > 0);

    NSError *error;
    BOOL success = [CurrentAppContext().keychainStorage setString:value
                                                          service:kKeychainService_LastRegistered
                                                              key:key
                                                            error:&error];
    if (!success || error) {
        OWSLogError(@"Error persisting 'last registered' value in keychain: %@", error);
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

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

@end

NS_ASSUME_NONNULL_END
