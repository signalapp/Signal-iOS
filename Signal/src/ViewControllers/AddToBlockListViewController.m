//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AddToBlockListViewController.h"
#import "CountryCodeViewController.h"
#import "PhoneNumber.h"
#import "StringUtil.h"
#import "UIFont+OWS.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <SignalServiceKit/PhoneNumberUtil.h>
#import <SignalServiceKit/OWSBlockingManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString * const kAddToBlockListViewControllerCellIdentifier = @"kAddToBlockListViewControllerCellIdentifier";

#pragma mark -

// TODO: Add a list of contacts to make it easier to block contacts.
@interface AddToBlockListViewController () <CountryCodeViewControllerDelegate, UITextFieldDelegate>

@property (nonatomic, readonly) OWSBlockingManager *blockingManager;

@property (nonatomic) UIButton *countryNameButton;
@property (nonatomic) UIButton *countryCodeButton;

@property (nonatomic) UITextField *phoneNumberTextField;

@property (nonatomic) UIButton *blockButton;

@property (nonatomic) NSString *callingCode;

@end

#pragma mark -

@implementation AddToBlockListViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
}

- (void)loadView
{
    [super loadView];
   
    self.view.backgroundColor = [UIColor whiteColor];
    
    _blockingManager = [OWSBlockingManager sharedManager];

    self.title = NSLocalizedString(@"SETTINGS_ADD_TO_BLOCK_LIST_TITLE", @"");

    [self createViews];
    
    [self populateDefaultCountryNameAndCode];

    [self addNotificationListeners];
}

- (void)addNotificationListeners
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockedPhoneNumbersDidChange:)
                                                 name:kNSNotificationName_BlockedPhoneNumbersDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)createViews {
    // Country Row
    UIView *countryRow = [self createRowWithHeight:60 previousRow:nil];

    _countryNameButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _countryNameButton.titleLabel.font = [UIFont ows_mediumFontWithSize:16.f];
    [_countryNameButton setTitleColor:[UIColor blackColor]
                             forState:UIControlStateNormal];
    [_countryNameButton setTitle:NSLocalizedString(@"REGISTRATION_DEFAULT_COUNTRY_NAME", @"")
                        forState:UIControlStateNormal];
    [_countryNameButton addTarget:self
                           action:@selector(showCountryCodeView:)
                 forControlEvents:UIControlEventTouchUpInside];
    [countryRow addSubview:_countryNameButton];
    [_countryNameButton autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:20.f];
    [_countryNameButton autoVCenterInSuperview];

    _countryCodeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _countryCodeButton.titleLabel.font = [UIFont ows_mediumFontWithSize:16.f];
    _countryCodeButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    [_countryCodeButton setTitleColor:[UIColor ows_signalBrandBlueColor]
                             forState:UIControlStateNormal];
    [_countryCodeButton addTarget:self
                           action:@selector(showCountryCodeView:)
                 forControlEvents:UIControlEventTouchUpInside];
    [countryRow addSubview:_countryCodeButton];
    [_countryCodeButton autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:16.f];
    [_countryCodeButton autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:_countryNameButton withOffset:0];
    [_countryCodeButton autoVCenterInSuperview];

    // Border Row
    UIView *borderRow1 = [self createRowWithHeight:1 previousRow:countryRow];
    UIColor *borderColor = [UIColor colorWithRed:0.75f green:0.75f blue:0.75f alpha:1.f];
    borderRow1.backgroundColor = borderColor;

    // Phone Number Row
    UIView *phoneNumberRow = [self createRowWithHeight:60 previousRow:borderRow1];

    UILabel *phoneNumberLabel = [UILabel new];
    phoneNumberLabel.font = [UIFont ows_mediumFontWithSize:16.f];
    phoneNumberLabel.textColor = [UIColor blackColor];
    phoneNumberLabel.text = NSLocalizedString(@"REGISTRATION_PHONENUMBER_BUTTON", @"");
    [phoneNumberRow addSubview:phoneNumberLabel];
    [phoneNumberLabel autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:20.f];
    [phoneNumberLabel autoVCenterInSuperview];

    _phoneNumberTextField = [UITextField new];
    _phoneNumberTextField.font = [UIFont ows_mediumFontWithSize:16.f];
    _phoneNumberTextField.textAlignment = NSTextAlignmentRight;
    _phoneNumberTextField.textColor = [UIColor ows_signalBrandBlueColor];
    _phoneNumberTextField.placeholder = NSLocalizedString(@"REGISTRATION_ENTERNUMBER_DEFAULT_TEXT", @"");
    _phoneNumberTextField.keyboardType = UIKeyboardTypeNumberPad;
    _phoneNumberTextField.delegate = self;
    [_phoneNumberTextField addTarget:self
                              action:@selector(textFieldDidChange:)
                    forControlEvents:UIControlEventEditingChanged];
    [phoneNumberRow addSubview:_phoneNumberTextField];
    [_phoneNumberTextField autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:16.f];
    [_phoneNumberTextField autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:phoneNumberLabel withOffset:0];
    [_phoneNumberTextField autoVCenterInSuperview];

    // Border Row
    UIView *borderRow2 = [self createRowWithHeight:1 previousRow:phoneNumberRow];
    borderRow2.backgroundColor = borderColor;

    // Block Button Row
    UIView *blockButtonRow = [self createRowWithHeight:60 previousRow:borderRow2];

    // TODO: Eventually we should make a view factory that will allow us to
    //       create views with consistent appearance across the app and move
    //       towards a "design language."
    _blockButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _blockButton.titleLabel.font = [UIFont ows_mediumFontWithSize:16.f];
    [_blockButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_blockButton setBackgroundColor:[UIColor ows_signalBrandBlueColor]];
    _blockButton.clipsToBounds = YES;
    _blockButton.layer.cornerRadius = 3.f;
    [_blockButton setTitle:NSLocalizedString(
                               @"BLOCK_LIST_VIEW_BLOCK_BUTTON", @"A label for the block button in the block list view")
                  forState:UIControlStateNormal];
    [_blockButton addTarget:self action:@selector(blockButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [blockButtonRow addSubview:_blockButton];
    [_blockButton autoCenterInSuperview];
    [_blockButton autoSetDimension:ALDimensionWidth toSize:160];
    [_blockButton autoSetDimension:ALDimensionHeight toSize:40];

    [self updateBlockButtonEnabling];
}

- (UIView *)createRowWithHeight:(CGFloat)height previousRow:(nullable UIView *)previousRow
{
    UIView *row = [UIView new];
    [self.view addSubview:row];
    [row autoPinWidthToSuperview];
    if (previousRow) {
        [row autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:previousRow withOffset:0];
    } else {
        [row autoPinToTopLayoutGuideOfViewController:self withInset:0];
    }
    [row autoSetDimension:ALDimensionHeight toSize:height];
    return row;
}

#pragma mark - Country

- (void)populateDefaultCountryNameAndCode {
    NSLocale *locale      = NSLocale.currentLocale;
    NSString *countryCode = [locale objectForKey:NSLocaleCountryCode];
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

    _callingCode = callingCode;

    NSString *title = [NSString stringWithFormat:@"%@ (%@)",
                       callingCode,
                       countryCode.uppercaseString];
    [_countryCodeButton setTitle:title
                        forState:UIControlStateNormal];
    [_countryCodeButton layoutSubviews];
}

- (void)setcallingCode:(NSString *)callingCode
{
    _callingCode = callingCode;

    [self updateBlockButtonEnabling];
}

#pragma mark - Actions

- (void)showCountryCodeView:(id)sender {
    CountryCodeViewController *countryCodeController = [[UIStoryboard storyboardWithName:@"Registration" bundle:NULL]
        instantiateViewControllerWithIdentifier:@"CountryCodeViewController"];
    countryCodeController.delegate = self;
    countryCodeController.shouldDismissWithoutSegue = YES;
    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:countryCodeController];
    [self presentViewController:navigationController animated:YES completion:[UIUtil modalCompletionBlock]];
}

- (void)blockButtonPressed:(id)sender
{
    [self tryToBlockPhoneNumber];
}

- (void)tryToBlockPhoneNumber
{
    if (![self hasValidPhoneNumber]) {
        return;
    }

    NSString *possiblePhoneNumber = [self.callingCode stringByAppendingString:_phoneNumberTextField.text.digitsOnly];
    PhoneNumber *parsedPhoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:possiblePhoneNumber];
    OWSAssert(parsedPhoneNumber);

    [_blockingManager addBlockedPhoneNumber:[parsedPhoneNumber toE164]];

    UIAlertController *controller = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"BLOCK_LIST_VIEW_BLOCKED_ALERT_TITLE",
                                     @"The title of the 'phone number blocked' alert in the block view.")
                         message:[NSString
                                     stringWithFormat:NSLocalizedString(@"BLOCK_LIST_VIEW_BLOCKED_ALERT_MESSAGE_FORMAT",
                                                          @"The message format of the 'phone number blocked' alert in "
                                                          @"the block view. It is populated with the blocked phone "
                                                          @"number."),
                                     [parsedPhoneNumber toE164]]
                  preferredStyle:UIAlertControllerStyleAlert];

    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                   style:UIAlertActionStyleDefault
                                                 handler:nil]];
    [self presentViewController:controller animated:YES completion:nil];

    _phoneNumberTextField.text = nil;
}

- (void)textFieldDidChange:(id)sender
{
    [self updateBlockButtonEnabling];
}

// TODO: We could also do this in registration view.
- (BOOL)hasValidPhoneNumber
{
    if (!self.callingCode) {
        return NO;
    }
    NSString *possiblePhoneNumber = [self.callingCode stringByAppendingString:_phoneNumberTextField.text.digitsOnly];
    PhoneNumber *parsedPhoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:possiblePhoneNumber];
    // It'd be nice to use [PhoneNumber isValid] but it always returns false for some countries
    // (like afghanistan) and there doesn't seem to be a good way to determine beforehand
    // which countries it can validate for without forking libPhoneNumber.
    return parsedPhoneNumber && parsedPhoneNumber.toE164.length > 1;
}

- (void)updateBlockButtonEnabling
{
    BOOL isEnabled = [self hasValidPhoneNumber];
    _blockButton.enabled = isEnabled;
    [_blockButton setBackgroundColor:(isEnabled ? [UIColor ows_signalBrandBlueColor] : [UIColor lightGrayColor])];
}

- (void)blockedPhoneNumbersDidChange:(id)notification
{
    // TODO: Once we have a list of contacts, we should update it here.
}

#pragma mark - CountryCodeViewControllerDelegate

- (void)countryCodeViewController:(CountryCodeViewController *)vc
             didSelectCountryCode:(NSString *)countryCode
                      countryName:(NSString *)countryName
                      callingCode:(NSString *)callingCode {

    [self updateCountryWithName:countryName
                    callingCode:callingCode
                    countryCode:countryCode];
}

#pragma mark - UITextFieldDelegate

// TODO: This logic resides in both RegistrationViewController and here.
//       We should refactor it out into a utility function.
- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
{
    [ViewControllerUtils phoneNumberTextField:textField
                shouldChangeCharactersInRange:range
                            replacementString:insertionText
                                  countryCode:_callingCode];

    [self updateBlockButtonEnabling];

    return NO; // inform our caller that we took care of performing the change
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    [self tryToBlockPhoneNumber];
    return NO;
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
