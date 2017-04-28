//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SelectRecipientViewController.h"
#import "ContactAccount.h"
#import "ContactTableViewCell.h"
#import "ContactsViewHelper.h"
#import "CountryCodeViewController.h"
#import "Environment.h"
#import "OWSAnyTouchGestureRecognizer.h"
#import "OWSContactsManager.h"
#import "OWSTableViewController.h"
#import "PhoneNumber.h"
#import "StringUtil.h"
#import "UIFont+OWS.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/PhoneNumberUtil.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kSelectRecipientViewControllerCellIdentifier = @"kSelectRecipientViewControllerCellIdentifier";

#pragma mark -

@interface SelectRecipientViewController () <CountryCodeViewControllerDelegate,
    ContactsViewHelperDelegate,
    OWSTableViewControllerDelegate,
    UITextFieldDelegate>

@property (nonatomic) UIButton *countryCodeButton;

@property (nonatomic) UITextField *phoneNumberTextField;

@property (nonatomic) UIButton *phoneNumberButton;

@property (nonatomic, readonly) OWSTableViewController *tableViewController;

@property (nonatomic) NSString *callingCode;

@end

#pragma mark -

@implementation SelectRecipientViewController

- (void)loadView
{
    [super loadView];

    self.view.backgroundColor = [UIColor whiteColor];
    [self.navigationController.navigationBar setTranslucent:NO];

    _contactsViewHelper = [ContactsViewHelper new];
    _contactsViewHelper.delegate = self;

    [self createViews];

    [self populateDefaultCountryNameAndCode];
}

- (void)viewDidLoad
{
    OWSAssert(self.tableViewController);

    [super viewDidLoad];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.tableViewController viewDidAppear:animated];

    if ([self.delegate shouldHideContacts]) {
        [self.phoneNumberTextField becomeFirstResponder];
    }
}

- (void)createViews
{
    OWSAssert(self.delegate);

    _tableViewController = [OWSTableViewController new];
    _tableViewController.delegate = self;
    [self.view addSubview:self.tableViewController.view];
    [_tableViewController.view autoPinWidthToSuperview];
    [_tableViewController.view autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [_tableViewController.view autoPinToBottomLayoutGuideOfViewController:self withInset:0];

    [self updateTableContents];

    [self updatePhoneNumberButtonEnabling];
}

- (UILabel *)countryCodeLabel
{
    UILabel *countryCodeLabel = [UILabel new];
    countryCodeLabel.font = [UIFont ows_mediumFontWithSize:18.f];
    countryCodeLabel.textColor = [UIColor blackColor];
    countryCodeLabel.text
        = NSLocalizedString(@"REGISTRATION_DEFAULT_COUNTRY_NAME", @"Label for the country code field");
    return countryCodeLabel;
}

- (UIButton *)countryCodeButton
{
    if (!_countryCodeButton) {
        _countryCodeButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _countryCodeButton.titleLabel.font = [UIFont ows_mediumFontWithSize:18.f];
        _countryCodeButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
        [_countryCodeButton setTitleColor:[UIColor ows_materialBlueColor] forState:UIControlStateNormal];
        [_countryCodeButton addTarget:self
                               action:@selector(showCountryCodeView:)
                     forControlEvents:UIControlEventTouchUpInside];
    }

    return _countryCodeButton;
}

- (UILabel *)phoneNumberLabel
{
    UILabel *phoneNumberLabel = [UILabel new];
    phoneNumberLabel.font = [UIFont ows_mediumFontWithSize:18.f];
    phoneNumberLabel.textColor = [UIColor blackColor];
    phoneNumberLabel.text
        = NSLocalizedString(@"REGISTRATION_PHONENUMBER_BUTTON", @"Label for the phone number textfield");
    return phoneNumberLabel;
}

- (UITextField *)phoneNumberTextField
{
    if (!_phoneNumberTextField) {
        _phoneNumberTextField = [UITextField new];
        _phoneNumberTextField.font = [UIFont ows_mediumFontWithSize:18.f];
        _phoneNumberTextField.textAlignment = NSTextAlignmentRight;
        _phoneNumberTextField.textColor = [UIColor ows_materialBlueColor];
        _phoneNumberTextField.placeholder = NSLocalizedString(
            @"REGISTRATION_ENTERNUMBER_DEFAULT_TEXT", @"Placeholder text for the phone number textfield");
        _phoneNumberTextField.keyboardType = UIKeyboardTypeNumberPad;
        _phoneNumberTextField.delegate = self;
        [_phoneNumberTextField addTarget:self
                                  action:@selector(textFieldDidChange:)
                        forControlEvents:UIControlEventEditingChanged];
    }

    return _phoneNumberTextField;
}

- (UIButton *)phoneNumberButton
{
    if (!_phoneNumberButton) {
        // TODO: Eventually we should make a view factory that will allow us to
        //       create views with consistent appearance across the app and move
        //       towards a "design language."
        _phoneNumberButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _phoneNumberButton.titleLabel.font = [UIFont ows_mediumFontWithSize:18.f];
        [_phoneNumberButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_phoneNumberButton setBackgroundColor:[UIColor ows_materialBlueColor]];
        _phoneNumberButton.clipsToBounds = YES;
        _phoneNumberButton.layer.cornerRadius = 3.f;
        [_phoneNumberButton setTitle:[self.delegate phoneNumberButtonText] forState:UIControlStateNormal];
        [_phoneNumberButton addTarget:self
                               action:@selector(phoneNumberButtonPressed:)
                     forControlEvents:UIControlEventTouchUpInside];
        [_phoneNumberButton autoSetDimension:ALDimensionWidth toSize:140];
        [_phoneNumberButton autoSetDimension:ALDimensionHeight toSize:40];
    }
    return _phoneNumberButton;
}

- (UIView *)createRowWithHeight:(CGFloat)height
                    previousRow:(nullable UIView *)previousRow
                      superview:(nullable UIView *)superview
{
    UIView *row = [UIView new];
    [superview addSubview:row];
    [row autoPinWidthToSuperview];
    if (previousRow) {
        [row autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:previousRow withOffset:0];
    } else {
        [row autoPinEdgeToSuperviewEdge:ALEdgeTop];
    }
    [row autoSetDimension:ALDimensionHeight toSize:height];
    return row;
}

#pragma mark - Country

- (void)populateDefaultCountryNameAndCode
{
    NSLocale *locale = NSLocale.currentLocale;
    NSString *countryCode = [locale objectForKey:NSLocaleCountryCode];
    NSNumber *callingCode = [[PhoneNumberUtil sharedUtil].nbPhoneNumberUtil getCountryCodeForRegion:countryCode];
    NSString *countryName = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
    [self updateCountryWithName:countryName
                    callingCode:[NSString stringWithFormat:@"%@%@", COUNTRY_CODE_PREFIX, callingCode]
                    countryCode:countryCode];
}

- (void)updateCountryWithName:(NSString *)countryName
                  callingCode:(NSString *)callingCode
                  countryCode:(NSString *)countryCode
{

    _callingCode = callingCode;

    NSString *title = [NSString stringWithFormat:@"%@ (%@)", callingCode, countryCode.uppercaseString];
    [self.countryCodeButton setTitle:title forState:UIControlStateNormal];
    [self.countryCodeButton layoutSubviews];
}

- (void)setCallingCode:(NSString *)callingCode
{
    _callingCode = callingCode;

    [self updatePhoneNumberButtonEnabling];
}

#pragma mark - Actions

- (void)showCountryCodeView:(nullable id)sender
{
    CountryCodeViewController *countryCodeController = [[UIStoryboard storyboardWithName:@"Registration" bundle:NULL]
        instantiateViewControllerWithIdentifier:@"CountryCodeViewController"];
    countryCodeController.delegate = self;
    countryCodeController.shouldDismissWithoutSegue = YES;
    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:countryCodeController];
    [self presentViewController:navigationController animated:YES completion:[UIUtil modalCompletionBlock]];
}

- (void)phoneNumberButtonPressed:(id)sender
{
    [self tryToSelectPhoneNumber];
}

- (void)tryToSelectPhoneNumber
{
    OWSAssert(self.delegate);

    if (![self hasValidPhoneNumber]) {
        OWSAssert(0);
        return;
    }

    NSMutableArray<NSString *> *possiblePhoneNumbers = [NSMutableArray new];
    for (PhoneNumber *phoneNumber in
        [PhoneNumber tryParsePhoneNumbersFromsUserSpecifiedText:self.phoneNumberTextField.text.digitsOnly
                                              clientPhoneNumber:[TSStorageManager localNumber]]) {
        [possiblePhoneNumbers addObject:phoneNumber.toE164];
    }
    if ([possiblePhoneNumbers count] < 1) {
        OWSAssert(0);
        return;
    }

    if ([self.delegate shouldValidatePhoneNumbers]) {
        // Show an alert while validating the recipient.
        __block BOOL wasCancelled = NO;
        UIAlertController *activityAlert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"ALERT_VALIDATE_RECIPIENT_TITLE",
                                         @"A title for the alert shown while validating a signal account")
                             message:NSLocalizedString(@"ALERT_VALIDATE_RECIPIENT_MESSAGE",
                                         @"A message for the alert shown while validating a signal account")
                      preferredStyle:UIAlertControllerStyleAlert];
        [activityAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                          style:UIAlertActionStyleCancel
                                                        handler:^(UIAlertAction *_Nonnull action) {
                                                            wasCancelled = YES;
                                                        }]];
        [ViewControllerUtils.topMostController presentViewController:activityAlert animated:YES completion:nil];

        __weak SelectRecipientViewController *weakSelf = self;
        [[ContactsUpdater sharedUpdater] lookupIdentifiers:possiblePhoneNumbers
            success:^(NSArray<SignalRecipient *> *recipients) {
                OWSAssert([NSThread isMainThread]);
                OWSAssert(recipients.count > 0);

                if (wasCancelled) {
                    return;
                }

                NSString *recipientId = recipients[0].uniqueId;
                [activityAlert dismissViewControllerAnimated:NO
                                                  completion:^{
                                                      [weakSelf.delegate phoneNumberWasSelected:recipientId];
                                                  }];
            }
            failure:^(NSError *error) {
                OWSAssert([NSThread isMainThread]);
                if (wasCancelled) {
                    return;
                }
                [activityAlert dismissViewControllerAnimated:NO
                                                  completion:^{
                                                      [ViewControllerUtils
                                                          showAlertWithTitle:NSLocalizedString(@"ALERT_ERROR_TITLE",
                                                                                 @"Title for a generic error alert.")
                                                                     message:error.localizedDescription];
                                                  }];
            }];
    } else {
        // Use just the first phone number.
        NSString *recipientId = possiblePhoneNumbers[0];
        [self.delegate phoneNumberWasSelected:recipientId];
    }
}

- (void)textFieldDidChange:(id)sender
{
    [self updatePhoneNumberButtonEnabling];
}

// TODO: We could also do this in registration view.
- (BOOL)hasValidPhoneNumber
{
    if (!self.callingCode) {
        return NO;
    }
    NSString *possiblePhoneNumber =
        [self.callingCode stringByAppendingString:self.phoneNumberTextField.text.digitsOnly];
    PhoneNumber *parsedPhoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:possiblePhoneNumber];
    // It'd be nice to use [PhoneNumber isValid] but it always returns false for some countries
    // (like afghanistan) and there doesn't seem to be a good way to determine beforehand
    // which countries it can validate for without forking libPhoneNumber.
    return parsedPhoneNumber && parsedPhoneNumber.toE164.length > 1;
}

- (void)updatePhoneNumberButtonEnabling
{
    BOOL isEnabled = [self hasValidPhoneNumber];
    self.phoneNumberButton.enabled = isEnabled;
    [self.phoneNumberButton
        setBackgroundColor:(isEnabled ? [UIColor ows_signalBrandBlueColor] : [UIColor lightGrayColor])];
}

#pragma mark - CountryCodeViewControllerDelegate

- (void)countryCodeViewController:(CountryCodeViewController *)vc
             didSelectCountryCode:(NSString *)countryCode
                      countryName:(NSString *)countryName
                      callingCode:(NSString *)callingCode
{

    [self updateCountryWithName:countryName callingCode:callingCode countryCode:countryCode];

    [self textField:self.phoneNumberTextField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@""];
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

    [self updatePhoneNumberButtonEnabling];

    return NO; // inform our caller that we took care of performing the change
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    [self tryToSelectPhoneNumber];
    return NO;
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak SelectRecipientViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;

    OWSTableSection *phoneNumberSection = [OWSTableSection new];
    phoneNumberSection.headerTitle = [self.delegate phoneNumberSectionTitle];
    const CGFloat kCountryRowHeight = 50;
    const CGFloat kPhoneNumberRowHeight = 50;
    const CGFloat kButtonRowHeight = 60;
    [phoneNumberSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
        SelectRecipientViewController *strongSelf = weakSelf;
        if (!strongSelf) {
            return (UITableViewCell *)nil;
        }

        UITableViewCell *cell = [UITableViewCell new];

        // Country Row
        UIView *countryRow = [self createRowWithHeight:kCountryRowHeight previousRow:nil superview:cell.contentView];
        [countryRow
            addGestureRecognizer:[[OWSAnyTouchGestureRecognizer alloc] initWithTarget:self
                                                                               action:@selector(countryRowTouched:)]];

        UILabel *countryCodeLabel = self.countryCodeLabel;
        [countryRow addSubview:countryCodeLabel];
        [countryCodeLabel autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:20.f];
        [countryCodeLabel autoVCenterInSuperview];

        [countryRow addSubview:self.countryCodeButton];
        [self.countryCodeButton autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:20.f];
        [self.countryCodeButton autoVCenterInSuperview];

        // Phone Number Row
        UIView *phoneNumberRow =
            [self createRowWithHeight:kPhoneNumberRowHeight previousRow:countryRow superview:cell.contentView];
        [phoneNumberRow addGestureRecognizer:[[OWSAnyTouchGestureRecognizer alloc]
                                                 initWithTarget:self
                                                         action:@selector(phoneNumberRowTouched:)]];

        UILabel *phoneNumberLabel = self.phoneNumberLabel;
        [phoneNumberRow addSubview:phoneNumberLabel];
        [phoneNumberLabel autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:20.f];
        [phoneNumberLabel autoVCenterInSuperview];

        [phoneNumberRow addSubview:self.phoneNumberTextField];
        [self.phoneNumberTextField autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:20.f];
        [self.phoneNumberTextField autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:phoneNumberLabel withOffset:0];
        [self.phoneNumberTextField autoVCenterInSuperview];

        // Phone Number Button Row
        UIView *buttonRow =
            [self createRowWithHeight:kButtonRowHeight previousRow:phoneNumberRow superview:cell.contentView];
        [buttonRow addSubview:self.phoneNumberButton];
        [self.phoneNumberButton autoVCenterInSuperview];
        [self.phoneNumberButton autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:20.f];

        [buttonRow autoPinEdgeToSuperviewEdge:ALEdgeBottom];

        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
                                                      customRowHeight:kCountryRowHeight + kPhoneNumberRowHeight
                                                      + kButtonRowHeight
                                                          actionBlock:nil]];
    [contents addSection:phoneNumberSection];

    if (![self.delegate shouldHideContacts]) {
        OWSTableSection *contactsSection = [OWSTableSection new];
        contactsSection.headerTitle = [self.delegate contactsSectionTitle];
        NSArray<ContactAccount *> *allRecipientContactAccounts = helper.allRecipientContactAccounts;
        if (allRecipientContactAccounts.count == 0) {
            // No Contacts

            [contactsSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
                UITableViewCell *cell = [UITableViewCell new];
                cell.textLabel.text = NSLocalizedString(
                    @"SETTINGS_BLOCK_LIST_NO_CONTACTS", @"A label that indicates the user has no Signal contacts.");
                cell.textLabel.font = [UIFont ows_regularFontWithSize:15.f];
                cell.textLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
                cell.textLabel.textAlignment = NSTextAlignmentCenter;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                return cell;
            }
                                                               actionBlock:nil]];
        } else {
            // Contacts

            for (ContactAccount *contactAccount in allRecipientContactAccounts) {
                [contactsSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
                    SelectRecipientViewController *strongSelf = weakSelf;
                    if (!strongSelf) {
                        return (ContactTableViewCell *)nil;
                    }

                    ContactTableViewCell *cell = [ContactTableViewCell new];
                    BOOL isBlocked = [helper isRecipientIdBlocked:contactAccount.recipientId];
                    if (isBlocked) {
                        cell.accessoryMessage = NSLocalizedString(
                            @"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
                    } else {
                        OWSAssert(cell.accessoryMessage == nil);
                    }
                    // TODO: Use the account label.
                    [cell configureWithContact:contactAccount.contact contactsManager:helper.contactsManager];
                    return cell;
                }
                                             customRowHeight:[ContactTableViewCell rowHeight]
                                             actionBlock:^{
                                                 [weakSelf.delegate contactAccountWasSelected:contactAccount];
                                             }]];
            }
        }
        [contents addSection:contactsSection];
    }

    self.tableViewController.contents = contents;
}

- (void)phoneNumberRowTouched:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self.phoneNumberTextField becomeFirstResponder];
    }
}

- (void)countryRowTouched:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self showCountryCodeView:nil];
    }
}

#pragma mark - OWSTableViewControllerDelegate

- (void)tableViewDidScroll
{
    [self.phoneNumberTextField resignFirstResponder];
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];
}

- (BOOL)shouldHideLocalNumber
{
    return [self.delegate shouldHideLocalNumber];
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
