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

    self.view.backgroundColor = [Theme backgroundColor];

    self.title = NSLocalizedString(@"ENABLE_2FA_VIEW_TITLE", @"Title for the 'enable two factor auth PIN' views.");

    [self createContents];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(stateDidChange:)
                                                 name:NSNotificationName_2FAStateDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
            OWSAssertDebug(![OWS2FAManager.sharedManager is2FAEnabled]);
            break;
    }

    [super viewWillAppear:animated];

    // If we're using a table, refresh its contents.
    [self updateTableContents];

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
    label.textColor = [Theme primaryColor];
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
    self.pinTextfield = [OWSTextField new];
    self.pinTextfield.textColor = [Theme primaryColor];
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

    [instructionsLabel autoPinTopToSuperviewMarginWithInset:kVSpacing];
    [instructionsLabel autoPinWidthToSuperviewWithMargin:self.hMargin];

    [self.pinTextfield autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:instructionsLabel withOffset:kVSpacing];
    [self.pinTextfield autoPinWidthToSuperviewWithMargin:self.hMargin];

    UIView *underscoreView = [UIView new];
    underscoreView.backgroundColor = [UIColor colorWithWhite:0.5 alpha:1.f];
    [self.view addSubview:underscoreView];
    [underscoreView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.pinTextfield withOffset:3];
    [underscoreView autoPinWidthToSuperviewWithMargin:self.hMargin];
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
        [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"BACK_BUTTON", @"button text for back button")
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
    [ViewControllerUtils ows2FAPINTextField:textField
              shouldChangeCharactersInRange:range
                          replacementString:insertionText];

    [self updateNavigationItems];

    return NO;
}

- (void)textFieldDidChange:(id)sender
{
    [self updateNavigationItems];
}

#pragma mark - Events

- (void)nextButtonWasPressed
{
    switch (self.mode) {
        case OWS2FASettingsMode_Status:
            OWSFailDebug(@"status mode should not have a next button.");
            return;
        case OWS2FASettingsMode_SelectPIN: {
            OWSAssertDebug(self.hasValidPin);

            OWS2FASettingsViewController *vc = [OWS2FASettingsViewController new];
            vc.mode = OWS2FASettingsMode_ConfirmPIN;
            vc.candidatePin = self.pinTextfield.text;
            OWSAssertDebug(self.root2FAViewController);
            vc.root2FAViewController = self.root2FAViewController;
            [self.navigationController pushViewController:vc animated:YES];
            break;
        }
        case OWS2FASettingsMode_ConfirmPIN: {
            OWSAssertDebug(self.hasValidPin);

            if ([self.pinTextfield.text isEqualToString:self.candidatePin]) {
                [self tryToEnable2FA];
            } else {
                // Clear the PIN so that the user can try again.
                self.pinTextfield.text = nil;

                [OWSAlerts showErrorAlertWithMessage:
                               NSLocalizedString(@"ENABLE_2FA_VIEW_PIN_DOES_NOT_MATCH",
                                   @"Error indicating that the entered 'two-factor auth PINs' do not match.")];
            }
            break;
        }
    }
}

- (BOOL)hasValidPin
{
    return self.pinTextfield.text.length >= kMin2FAPinLength;
}

- (void)showEnable2FAWorkUI
{
    OWSAssertDebug(![OWS2FAManager.sharedManager is2FAEnabled]);

    OWSLogInfo(@"");

    OWS2FASettingsViewController *vc = [OWS2FASettingsViewController new];
    vc.mode = OWS2FASettingsMode_SelectPIN;
    vc.root2FAViewController = self;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tryToDisable2FA
{
    OWSLogInfo(@"");

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
                                  [weakSelf updateTableContents];

                                  [OWSAlerts showErrorAlertWithMessage:
                                                 NSLocalizedString(@"ENABLE_2FA_VIEW_COULD_NOT_DISABLE_2FA",
                                                     @"Error indicating that attempt to disable 'two-factor "
                                                     @"auth' failed.")];
                              }];
                          }];
                  }];
}

- (void)tryToEnable2FA
{
    OWSAssertDebug(self.candidatePin.length > 0);

    OWSLogInfo(@"");

    __weak OWS2FASettingsViewController *weakSelf = self;

    [ModalActivityIndicatorViewController
        presentFromViewController:self
                        canCancel:NO
                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                      [OWS2FAManager.sharedManager requestEnable2FAWithPin:self.candidatePin
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

                                  [OWSAlerts showErrorAlertWithMessage:
                                                 NSLocalizedString(@"ENABLE_2FA_VIEW_COULD_NOT_ENABLE_2FA",
                                                     @"Error indicating that attempt to enable 'two-factor "
                                                     @"auth' failed.")];
                              }];
                          }];
                  }];
}

- (void)showCompleteUI
{
    OWSAssertDebug([OWS2FAManager.sharedManager is2FAEnabled]);
    OWSAssertDebug(self.root2FAViewController);

    OWSLogInfo(@"");

    [self.navigationController popToViewController:self.root2FAViewController animated:YES];
}

- (void)backButtonWasPressed
{
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)stateDidChange:(NSNotification *)notification
{
    OWSLogInfo(@"");

    if (self.mode == OWS2FASettingsMode_Status) {
        [self createContents];
    }
}

@end

NS_ASSUME_NONNULL_END
