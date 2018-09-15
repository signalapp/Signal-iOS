//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SelectRecipientViewController.h"
#import "CountryCodeViewController.h"
#import "PhoneNumber.h"
#import "ViewControllerUtils.h"
#import <SignalMessaging/ContactTableViewCell.h>
#import <SignalMessaging/ContactsViewHelper.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSTableViewController.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIFont+OWS.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalMessaging/UIView+OWS.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/PhoneNumberUtil.h>
#import <SignalServiceKit/SignalAccount.h>
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

@property (nonatomic) OWSFlatButton *phoneNumberButton;

@property (nonatomic) UILabel *examplePhoneNumberLabel;

@property (nonatomic, readonly) OWSTableViewController *tableViewController;

@property (nonatomic) NSString *callingCode;

@end

#pragma mark -

@implementation SelectRecipientViewController

- (void)loadView
{
    [super loadView];

    self.view.backgroundColor = [Theme backgroundColor];

    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];

    [self createViews];

    [self populateDefaultCountryNameAndCode];

    if (self.delegate.shouldHideContacts) {
        self.tableViewController.tableView.scrollEnabled = NO;
    }
}

- (void)viewDidLoad
{
    OWSAssertDebug(self.tableViewController);

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
    OWSAssertDebug(self.delegate);

    _tableViewController = [OWSTableViewController new];
    _tableViewController.delegate = self;
    [self.view addSubview:self.tableViewController.view];
    [_tableViewController.view autoPinWidthToSuperview];
    [_tableViewController.view autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [_tableViewController.view autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    self.tableViewController.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableViewController.tableView.estimatedRowHeight = 60;
    _tableViewController.view.backgroundColor = [Theme backgroundColor];

    [self updateTableContents];

    [self updatePhoneNumberButtonEnabling];
}

- (UILabel *)countryCodeLabel
{
    UILabel *countryCodeLabel = [UILabel new];
    countryCodeLabel.font = [UIFont ows_mediumFontWithSize:18.f];
    countryCodeLabel.textColor = [Theme primaryColor];
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
    phoneNumberLabel.textColor = [Theme primaryColor];
    phoneNumberLabel.text
        = NSLocalizedString(@"REGISTRATION_PHONENUMBER_BUTTON", @"Label for the phone number textfield");
    return phoneNumberLabel;
}

- (UIFont *)examplePhoneNumberFont
{
    return [UIFont ows_regularFontWithSize:16.f];
}

- (UILabel *)examplePhoneNumberLabel
{
    if (!_examplePhoneNumberLabel) {
        _examplePhoneNumberLabel = [UILabel new];
        _examplePhoneNumberLabel.font = [self examplePhoneNumberFont];
        _examplePhoneNumberLabel.textColor = [Theme secondaryColor];
    }

    return _examplePhoneNumberLabel;
}

- (UITextField *)phoneNumberTextField
{
    if (!_phoneNumberTextField) {
        _phoneNumberTextField = [OWSTextField new];
        _phoneNumberTextField.font = [UIFont ows_mediumFontWithSize:18.f];
        _phoneNumberTextField.textAlignment = _phoneNumberTextField.textAlignmentUnnatural;
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

- (OWSFlatButton *)phoneNumberButton
{
    if (!_phoneNumberButton) {
        const CGFloat kButtonHeight = 40;
        OWSFlatButton *button = [OWSFlatButton buttonWithTitle:[self.delegate phoneNumberButtonText]
                                                          font:[OWSFlatButton fontForHeight:kButtonHeight]
                                                    titleColor:[UIColor whiteColor]
                                               backgroundColor:[UIColor ows_materialBlueColor]
                                                        target:self
                                                      selector:@selector(phoneNumberButtonPressed)];
        _phoneNumberButton = button;
        [button autoSetDimension:ALDimensionWidth toSize:140];
        [button autoSetDimension:ALDimensionHeight toSize:kButtonHeight];
    }
    return _phoneNumberButton;
}

- (UIView *)createRowWithHeight:(CGFloat)height
                    previousRow:(nullable UIView *)previousRow
                      superview:(nullable UIView *)superview
{
    UIView *row = [UIView containerView];
    [superview addSubview:row];
    [row autoPinLeadingAndTrailingToSuperviewMargin];
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
    PhoneNumber *localNumber = [PhoneNumber phoneNumberFromE164:[TSAccountManager localNumber]];
    OWSAssertDebug(localNumber);

    NSString *countryCode;
    NSNumber *callingCode;
    if (localNumber) {
        callingCode = [localNumber getCountryCode];
        OWSAssertDebug(callingCode);
        if (callingCode) {
            NSString *prefix = [NSString stringWithFormat:@"+%d", callingCode.intValue];
            countryCode = [[PhoneNumberUtil sharedThreadLocal] probableCountryCodeForCallingCode:prefix];
        }
    }

    if (!countryCode || !callingCode) {
        countryCode = [PhoneNumber defaultCountryCode];
        callingCode = [[PhoneNumberUtil sharedThreadLocal].nbPhoneNumberUtil getCountryCodeForRegion:countryCode];
    }

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

    NSString *titleFormat = (CurrentAppContext().isRTL ? @"(%2$@) %1$@" : @"%1$@ (%2$@)");
    NSString *title = [NSString stringWithFormat:titleFormat, callingCode, countryCode.localizedUppercaseString];
    [self.countryCodeButton setTitle:title forState:UIControlStateNormal];
    [self.countryCodeButton layoutSubviews];

    self.examplePhoneNumberLabel.text =
        [ViewControllerUtils examplePhoneNumberForCountryCode:countryCode callingCode:callingCode];
    [self.examplePhoneNumberLabel.superview layoutSubviews];
}

- (void)setCallingCode:(NSString *)callingCode
{
    _callingCode = callingCode;

    [self updatePhoneNumberButtonEnabling];
}

#pragma mark - Actions

- (void)showCountryCodeView:(nullable id)sender
{
    CountryCodeViewController *countryCodeController = [CountryCodeViewController new];
    countryCodeController.countryCodeDelegate = self;
    countryCodeController.isPresentedInNavigationController = self.isPresentedInNavigationController;
    if (self.isPresentedInNavigationController) {
        [self.navigationController pushViewController:countryCodeController animated:YES];
    } else {
        OWSNavigationController *navigationController =
            [[OWSNavigationController alloc] initWithRootViewController:countryCodeController];
        [self presentViewController:navigationController animated:YES completion:nil];
    }
}

- (void)phoneNumberButtonPressed
{
    [self tryToSelectPhoneNumber];
}

- (void)tryToSelectPhoneNumber
{
    OWSAssertDebug(self.delegate);

    if (![self hasValidPhoneNumber]) {
        OWSFailDebug(@"Invalid phone number was selected.");
        return;
    }

    NSString *rawPhoneNumber = [self.callingCode stringByAppendingString:self.phoneNumberTextField.text.digitsOnly];

    NSMutableArray<NSString *> *possiblePhoneNumbers = [NSMutableArray new];
    for (PhoneNumber *phoneNumber in
        [PhoneNumber tryParsePhoneNumbersFromsUserSpecifiedText:rawPhoneNumber
                                              clientPhoneNumber:[TSAccountManager localNumber]]) {
        [possiblePhoneNumbers addObject:phoneNumber.toE164];
    }
    if ([possiblePhoneNumbers count] < 1) {
        OWSFailDebug(@"Couldn't parse phone number.");
        return;
    }

    [self.phoneNumberTextField resignFirstResponder];

    // There should only be one phone number, since we're explicitly specifying
    // a country code and therefore parsing a number in e164 format.
    OWSAssertDebug([possiblePhoneNumbers count] == 1);

    if ([self.delegate shouldValidatePhoneNumbers]) {
        // Show an alert while validating the recipient.

        __weak SelectRecipientViewController *weakSelf = self;
        [ModalActivityIndicatorViewController
            presentFromViewController:self
                            canCancel:YES
                      backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                          [[ContactsUpdater sharedUpdater] lookupIdentifiers:possiblePhoneNumbers
                              success:^(NSArray<SignalRecipient *> *recipients) {
                                  OWSAssertIsOnMainThread();
                                  if (modalActivityIndicator.wasCancelled) {
                                      return;
                                  }

                                  if (recipients.count == 0) {
                                      [modalActivityIndicator
                                          dismissViewControllerAnimated:NO
                                                             completion:^{
                                                                 NSError *error
                                                                     = OWSErrorMakeNoSuchSignalRecipientError();
                                                                 [OWSAlerts showErrorAlertWithMessage:
                                                                                error.localizedDescription];
                                                             }];
                                      return;
                                  }

                                  NSString *recipientId = recipients[0].uniqueId;
                                  [modalActivityIndicator
                                      dismissViewControllerAnimated:NO
                                                         completion:^{
                                                             [weakSelf.delegate phoneNumberWasSelected:recipientId];
                                                         }];
                              }
                              failure:^(NSError *error) {
                                  OWSAssertIsOnMainThread();
                                  if (modalActivityIndicator.wasCancelled) {
                                      return;
                                  }
                                  [modalActivityIndicator
                                      dismissViewControllerAnimated:NO
                                                         completion:^{
                                                             [OWSAlerts
                                                                 showErrorAlertWithMessage:error.localizedDescription];
                                                         }];
                              }];
                      }];
    } else {
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
    NSArray<PhoneNumber *> *parsePhoneNumbers =
        [PhoneNumber tryParsePhoneNumbersFromsUserSpecifiedText:possiblePhoneNumber
                                              clientPhoneNumber:[TSAccountManager localNumber]];
    if (parsePhoneNumbers.count < 1) {
        return NO;
    }
    PhoneNumber *parsedPhoneNumber = parsePhoneNumbers[0];
    // It'd be nice to use [PhoneNumber isValid] but it always returns false for some countries
    // (like afghanistan) and there doesn't seem to be a good way to determine beforehand
    // which countries it can validate for without forking libPhoneNumber.
    return parsedPhoneNumber.toE164.length > 1;
}

- (void)updatePhoneNumberButtonEnabling
{
    BOOL isEnabled = [self hasValidPhoneNumber];
    self.phoneNumberButton.enabled = isEnabled;
    [self.phoneNumberButton
        setBackgroundColorsWithUpColor:(isEnabled ? [UIColor ows_signalBrandBlueColor] : [Theme secondaryColor])];
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
    if ([self hasValidPhoneNumber]) {
        [self tryToSelectPhoneNumber];
    }
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
    const CGFloat examplePhoneNumberRowHeight = self.examplePhoneNumberFont.lineHeight + 3.f;
    const CGFloat kButtonRowHeight = 60;
    [phoneNumberSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
        SelectRecipientViewController *strongSelf = weakSelf;
        OWSCAssertDebug(strongSelf);

        UITableViewCell *cell = [OWSTableItem newCell];
        cell.preservesSuperviewLayoutMargins = YES;
        cell.contentView.preservesSuperviewLayoutMargins = YES;

        // Country Row
        UIView *countryRow =
            [strongSelf createRowWithHeight:kCountryRowHeight previousRow:nil superview:cell.contentView];
        [countryRow addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:strongSelf
                                                                                 action:@selector(countryRowTouched:)]];

        UILabel *countryCodeLabel = strongSelf.countryCodeLabel;
        [countryRow addSubview:countryCodeLabel];
        [countryCodeLabel autoPinLeadingToSuperviewMargin];
        [countryCodeLabel autoVCenterInSuperview];

        [countryRow addSubview:strongSelf.countryCodeButton];
        [strongSelf.countryCodeButton autoPinTrailingToSuperviewMargin];
        [strongSelf.countryCodeButton autoVCenterInSuperview];

        // Phone Number Row
        UIView *phoneNumberRow =
            [strongSelf createRowWithHeight:kPhoneNumberRowHeight previousRow:countryRow superview:cell.contentView];
        [phoneNumberRow
            addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:strongSelf
                                                                         action:@selector(phoneNumberRowTouched:)]];

        UILabel *phoneNumberLabel = strongSelf.phoneNumberLabel;
        [phoneNumberRow addSubview:phoneNumberLabel];
        [phoneNumberLabel autoPinLeadingToSuperviewMargin];
        [phoneNumberLabel autoVCenterInSuperview];

        [phoneNumberRow addSubview:strongSelf.phoneNumberTextField];
        [strongSelf.phoneNumberTextField autoPinLeadingToTrailingEdgeOfView:phoneNumberLabel offset:10.f];
        [strongSelf.phoneNumberTextField autoPinTrailingToSuperviewMargin];
        [strongSelf.phoneNumberTextField autoVCenterInSuperview];

        // Example row.
        UIView *examplePhoneNumberRow = [strongSelf createRowWithHeight:examplePhoneNumberRowHeight
                                                            previousRow:phoneNumberRow
                                                              superview:cell.contentView];
        [examplePhoneNumberRow addSubview:strongSelf.examplePhoneNumberLabel];
        [strongSelf.examplePhoneNumberLabel autoVCenterInSuperview];
        [strongSelf.examplePhoneNumberLabel autoPinTrailingToSuperviewMargin];

        // Phone Number Button Row
        UIView *buttonRow = [strongSelf createRowWithHeight:kButtonRowHeight
                                                previousRow:examplePhoneNumberRow
                                                  superview:cell.contentView];
        [buttonRow addSubview:strongSelf.phoneNumberButton];
        [strongSelf.phoneNumberButton autoVCenterInSuperview];
        [strongSelf.phoneNumberButton autoPinTrailingToSuperviewMargin];

        [buttonRow autoPinEdgeToSuperviewEdge:ALEdgeBottom];

        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
                                                      customRowHeight:kCountryRowHeight + kPhoneNumberRowHeight
                                                      + examplePhoneNumberRowHeight + kButtonRowHeight
                                                          actionBlock:nil]];
    [contents addSection:phoneNumberSection];

    if (![self.delegate shouldHideContacts]) {
        OWSTableSection *contactsSection = [OWSTableSection new];
        contactsSection.headerTitle = [self.delegate contactsSectionTitle];
        NSArray<SignalAccount *> *signalAccounts = helper.signalAccounts;
        if (signalAccounts.count == 0) {
            // No Contacts

            [contactsSection
                addItem:[OWSTableItem softCenterLabelItemWithText:
                                          NSLocalizedString(@"SETTINGS_BLOCK_LIST_NO_CONTACTS",
                                              @"A label that indicates the user has no Signal contacts.")]];
        } else {
            // Contacts

            for (SignalAccount *signalAccount in signalAccounts) {
                [contactsSection
                    addItem:[OWSTableItem
                                itemWithCustomCellBlock:^{
                                    SelectRecipientViewController *strongSelf = weakSelf;
                                    OWSCAssertDebug(strongSelf);

                                    ContactTableViewCell *cell = [ContactTableViewCell new];
                                    BOOL isBlocked = [helper isRecipientIdBlocked:signalAccount.recipientId];
                                    if (isBlocked) {
                                        cell.accessoryMessage = NSLocalizedString(@"CONTACT_CELL_IS_BLOCKED",
                                            @"An indicator that a contact has been blocked.");
                                    } else {
                                        cell.accessoryMessage =
                                            [weakSelf.delegate accessoryMessageForSignalAccount:signalAccount];
                                    }
                                    [cell configureWithRecipientId:signalAccount.recipientId
                                                   contactsManager:helper.contactsManager];

                                    if (![weakSelf.delegate canSignalAccountBeSelected:signalAccount]) {
                                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
                                    }

                                    return cell;
                                }
                                customRowHeight:UITableViewAutomaticDimension
                                actionBlock:^{
                                    if (![weakSelf.delegate canSignalAccountBeSelected:signalAccount]) {
                                        return;
                                    }
                                    [weakSelf.delegate signalAccountWasSelected:signalAccount];
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

- (void)tableViewWillBeginDragging
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

@end

NS_ASSUME_NONNULL_END
