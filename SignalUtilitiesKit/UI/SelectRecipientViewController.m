//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalUtilitiesKit/SelectRecipientViewController.h>

#import <SignalUtilitiesKit/ContactTableViewCell.h>
#import <SignalUtilitiesKit/OWSTableViewController.h>
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>
#import <SignalUtilitiesKit/UIFont+OWS.h>
#import <SignalUtilitiesKit/UIUtil.h>
#import <SessionUtilitiesKit/UIView+OWS.h>
#import <SessionUtilitiesKit/AppContext.h>
#import <SignalUtilitiesKit/SignalAccount.h>
#import <SessionMessagingKit/TSAccountManager.h>
#import <SignalUtilitiesKit/OWSTextField.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kSelectRecipientViewControllerCellIdentifier = @"kSelectRecipientViewControllerCellIdentifier";

#pragma mark -

@interface SelectRecipientViewController () </*CountryCodeViewControllerDelegate,*/
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

    [self createViews];

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
    [self.tableViewController.view autoPinEdgeToSuperviewSafeArea:ALEdgeLeading];
    [self.tableViewController.view autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];
    [_tableViewController.view autoPinEdge:ALEdgeTop toEdge:ALEdgeTop ofView:self.view withOffset:0];
    [_tableViewController.view autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    self.tableViewController.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableViewController.tableView.estimatedRowHeight = 60;
    _tableViewController.view.backgroundColor = [Theme backgroundColor];

    [self updateTableContents];
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
        SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _countryCodeButton);
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
        SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _examplePhoneNumberLabel);
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
        SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _phoneNumberTextField);
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
        SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _phoneNumberButton);
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

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
{
    return NO; // inform our caller that we took care of performing the change
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
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
