//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "ProfileViewController.h"
#import "AppDelegate.h"
#import "AvatarViewHelper.h"
#import "HomeViewController.h"
#import "OWSNavigationController.h"
#import "Signal-Swift.h"
#import "SignalsNavigationController.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/OWSNavigationController.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalMessaging/UIViewController+OWS.h>

@import SafariServices;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ProfileViewMode) {
    ProfileViewMode_AppSettings = 0,
    ProfileViewMode_Registration,
};

NSString *const kProfileView_LastPresentedDate = @"kProfileView_LastPresentedDate";

@interface ProfileViewController () <UITextFieldDelegate, AvatarViewHelperDelegate, OWSNavigationView>

@property (nonatomic, readonly) AvatarViewHelper *avatarViewHelper;

@property (nonatomic) UITextField *profileNameTextField;

@property (nonatomic) UILabel *usernameLabel;

@property (nonatomic) AvatarImageView *avatarView;

@property (nonatomic) UIImageView *cameraImageView;

@property (nonatomic) OWSFlatButton *saveButton;

@property (nonatomic, nullable) UIImage *avatar;

@property (nonatomic) BOOL hasUnsavedChanges;

@property (nonatomic) ProfileViewMode profileViewMode;

@end

#pragma mark -

@implementation ProfileViewController

#pragma mark - Dependencies

+ (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

+ (SDSKeyValueStore *)keyValueStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"kProfileView_Collection"];
}

#pragma mark -

- (instancetype)initWithMode:(ProfileViewMode)profileViewMode
{
    self = [super init];

    if (!self) {
        return self;
    }

    self.profileViewMode = profileViewMode;

    [ProfileViewController.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [ProfileViewController.keyValueStore setDate:[NSDate new]
                                                 key:kProfileView_LastPresentedDate
                                         transaction:transaction];
    }];

    return self;
}

- (void)loadView
{
    [super loadView];

    self.title = NSLocalizedString(@"PROFILE_VIEW_TITLE", @"Title for the profile view.");

    _avatarViewHelper = [AvatarViewHelper new];
    _avatarViewHelper.delegate = self;

    _avatar = [OWSProfileManager.sharedManager localProfileAvatarImage];

    [self createViews];
    [self updateNavigationItem];

    if (self.profileViewMode == ProfileViewMode_Registration) {
        // mark as dirty if re-registration has content
        if (self.profileNameTextField.text.length > 0 || self.avatar != nil) {
            self.hasUnsavedChanges = YES;
        }
    }
}

- (void)createViews
{
    self.view.backgroundColor = Theme.backgroundColor;

    UIStackView *stackView = [UIStackView new];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 0;

    [self.view addSubview:stackView];

    [stackView autoPinToTopLayoutGuideOfViewController:self withInset:15.f];
    [stackView autoPinWidthToSuperview];

    void (^addSeparator)(BOOL) = ^(BOOL withLeadingInset) {
        UIView *separatorWrapper = [UIView containerView];
        [stackView addArrangedSubview:separatorWrapper];
        UIView *separator = [UIView containerView];
        separator.backgroundColor = Theme.cellSeparatorColor;
        [separatorWrapper addSubview:separator];
        [separator autoPinHeightToSuperview];
        [separator autoPinLeadingToSuperviewMarginWithInset:withLeadingInset ? 18 : 0];
        [separator autoPinTrailingToSuperviewMargin];
        [separator autoSetDimension:ALDimensionHeight toSize:CGHairlineWidth()];
    };

    CGFloat rowSpacing = 10;
    UIEdgeInsets rowMargins = UIEdgeInsetsMake(10, 18, 10, 18);

    // Avatar

    UIView *avatarRow = [UIView containerView];
    [stackView addArrangedSubview:avatarRow];

    self.avatarView = [AvatarImageView new];
    self.avatarView.userInteractionEnabled = YES;
    self.avatarView.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"avatarView");

    [self.avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                  action:@selector(avatarViewTapped:)]];

    [avatarRow addSubview:self.avatarView];
    [self.avatarView autoHCenterInSuperview];
    [self.avatarView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.avatarView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:28];
    [self.avatarView autoSetDimension:ALDimensionWidth toSize:self.avatarSize];
    [self.avatarView autoSetDimension:ALDimensionHeight toSize:self.avatarSize];

    self.cameraImageView = [UIImageView new];
    [self.cameraImageView setTemplateImageName:@"camera-outline-24" tintColor:Theme.secondaryColor];
    [self.cameraImageView autoSetDimensionsToSize:CGSizeMake(32, 32)];
    self.cameraImageView.contentMode = UIViewContentModeCenter;
    self.cameraImageView.backgroundColor = Theme.backgroundColor;
    self.cameraImageView.layer.cornerRadius = 16;
    self.cameraImageView.layer.shadowColor =
        [(Theme.isDarkThemeEnabled ? Theme.darkThemeOffBackgroundColor : Theme.primaryColor) CGColor];
    self.cameraImageView.layer.shadowOffset = CGSizeMake(1, 1);
    self.cameraImageView.layer.shadowOpacity = 0.5;
    self.cameraImageView.layer.shadowRadius = 4;

    [avatarRow addSubview:self.cameraImageView];
    [self.cameraImageView autoPinTrailingToEdgeOfView:self.avatarView];
    [self.cameraImageView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.avatarView];

    [self updateAvatarView];

    addSeparator(NO);

    // Name

    UIStackView *profileNameRow = [UIStackView new];
    profileNameRow.spacing = rowSpacing;
    profileNameRow.layoutMarginsRelativeArrangement = YES;
    profileNameRow.layoutMargins = rowMargins;
    [profileNameRow
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(profileNameRowTapped:)]];
    profileNameRow.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"profileNameRow");
    [stackView addArrangedSubview:profileNameRow];

    UILabel *profileNameLabel = [UILabel new];
    profileNameLabel.text = NSLocalizedString(
        @"PROFILE_VIEW_PROFILE_NAME_FIELD", @"Label for the profile name field of the profile view.");
    profileNameLabel.textColor = Theme.primaryColor;
    profileNameLabel.font = [[UIFont ows_dynamicTypeBodyClampedFont] ows_mediumWeight];
    [profileNameRow addArrangedSubview:profileNameLabel];

    UITextField *profileNameTextField = [OWSTextField new];
    _profileNameTextField = profileNameTextField;
    profileNameTextField.returnKeyType = UIReturnKeyDone;
    profileNameTextField.font = [UIFont ows_dynamicTypeBodyClampedFont];
    profileNameTextField.textColor = Theme.primaryColor;
    profileNameTextField.placeholder = NSLocalizedString(
        @"PROFILE_VIEW_NAME_DEFAULT_TEXT", @"Default text for the profile name field of the profile view.");
    profileNameTextField.delegate = self;
    profileNameTextField.text = [OWSProfileManager.sharedManager localProfileName];
    profileNameTextField.textAlignment = NSTextAlignmentRight;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, profileNameTextField);
    [profileNameTextField addTarget:self
                             action:@selector(textFieldDidChange:)
                   forControlEvents:UIControlEventEditingChanged];
    [profileNameRow addArrangedSubview:profileNameTextField];

    // Username

    if (SSKFeatureFlags.usernames) {
        addSeparator(YES);

        UIStackView *usernameRow = [UIStackView new];
        usernameRow.spacing = rowSpacing;
        usernameRow.layoutMarginsRelativeArrangement = YES;
        usernameRow.layoutMargins = rowMargins;
        [usernameRow
            addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(usernameRowTapped:)]];
        usernameRow.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"nameRow");
        [stackView addArrangedSubview:usernameRow];

        UILabel *usernameTitleLabel = [UILabel new];
        usernameTitleLabel.text
            = NSLocalizedString(@"PROFILE_VIEW_USERNAME_FIELD", @"Label for the username field of the profile view.");
        usernameTitleLabel.textColor = Theme.primaryColor;
        usernameTitleLabel.font = [[UIFont ows_dynamicTypeBodyClampedFont] ows_mediumWeight];
        [usernameRow addArrangedSubview:usernameTitleLabel];

        UILabel *usernameLabel = [UILabel new];

        usernameLabel.font = [UIFont ows_dynamicTypeBodyClampedFont];
        usernameLabel.textAlignment = NSTextAlignmentRight;
        [usernameRow addArrangedSubview:usernameLabel];

        _usernameLabel = usernameLabel;

        UIView *disclosureImageContainer = [UIView containerView];
        [usernameRow addArrangedSubview:disclosureImageContainer];

        NSString *disclosureImageName
            = CurrentAppContext().isRTL ? @"system_disclosure_indicator_rtl" : @"system_disclosure_indicator";
        UIImageView *disclosureImageView = [UIImageView new];
        [disclosureImageView setTemplateImageName:disclosureImageName tintColor:Theme.cellSeparatorColor];

        [disclosureImageContainer addSubview:disclosureImageView];
        [disclosureImageView autoPinWidthToSuperview];
        [disclosureImageView autoVCenterInSuperview];
        [disclosureImageView autoSetDimension:ALDimensionHeight toSize:13];
        [disclosureImageView autoSetDimension:ALDimensionWidth toSize:11];

        [self updateUsername];

        addSeparator(NO);
    } else {
        addSeparator(NO);
    }

    // Information

    UIView *infoRow = [UIView new];
    infoRow.layoutMargins = rowMargins;
    [infoRow
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(infoRowTapped:)]];
    infoRow.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"infoRow");
    [stackView addArrangedSubview:infoRow];

    UILabel *infoLabel = [UILabel new];
    infoLabel.textColor = Theme.secondaryColor;
    infoLabel.font = [UIFont ows_dynamicTypeCaption1ClampedFont];
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:NSLocalizedString(@"PROFILE_VIEW_PROFILE_DESCRIPTION",
                                                        @"Description of the user profile.")
                                         attributes:@{}]];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:@{}]];
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:NSLocalizedString(@"PROFILE_VIEW_PROFILE_DESCRIPTION_LINK",
                                                        @"Link to more information about the user profile.")
                                         attributes:@{
                                             NSUnderlineStyleAttributeName : @(NSUnderlineStyleNone),
                                             NSForegroundColorAttributeName : [UIColor ows_materialBlueColor],
                                         }]];
    infoLabel.attributedText = text;
    infoLabel.numberOfLines = 0;
    infoLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [infoRow addSubview:infoLabel];
    [infoLabel autoPinEdgesToSuperviewMargins];

    // Big Button

    if (self.profileViewMode == ProfileViewMode_Registration) {
        UIView *buttonRow = [UIView new];
        buttonRow.layoutMargins = rowMargins;
        [stackView addArrangedSubview:buttonRow];

        const CGFloat kButtonHeight = 47.f;
        // NOTE: We use ows_signalBrandBlueColor instead of ows_materialBlueColor
        //       throughout the onboarding flow to be consistent with the headers.
        OWSFlatButton *saveButton =
            [OWSFlatButton buttonWithTitle:NSLocalizedString(@"PROFILE_VIEW_SAVE_BUTTON",
                                               @"Button to save the profile view in the profile view.")
                                      font:[OWSFlatButton fontForHeight:kButtonHeight]
                                titleColor:[UIColor whiteColor]
                           backgroundColor:[UIColor ows_signalBrandBlueColor]
                                    target:self
                                  selector:@selector(saveButtonPressed)];
        SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, saveButton);
        self.saveButton = saveButton;
        [buttonRow addSubview:saveButton];
        [saveButton autoPinEdgesToSuperviewMargins];
        [saveButton autoSetDimension:ALDimensionHeight toSize:47.f];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self updateUsername];
}

#pragma mark - Event Handling

- (void)backOrSkipButtonPressed
{
    [self leaveViewCheckingForUnsavedChanges];
}

- (void)leaveViewCheckingForUnsavedChanges
{
    [self.profileNameTextField resignFirstResponder];

    if (!self.hasUnsavedChanges) {
        // If user made no changes, return to conversation settings view.
        [self profileCompletedOrSkipped];
        return;
    }
 
    __weak ProfileViewController *weakSelf = self;
    [OWSAlerts showPendingChangesAlertWithDiscardAction:^{
        [weakSelf profileCompletedOrSkipped];
    }];
}

- (void)avatarTapped
{
    [self.avatarViewHelper showChangeAvatarUI];
}

- (void)setHasUnsavedChanges:(BOOL)hasUnsavedChanges
{
    _hasUnsavedChanges = hasUnsavedChanges;

    [self updateNavigationItem];
}

- (void)updateNavigationItem
{
    // The navigation bar is hidden in the registration workflow.
    if (self.navigationController.navigationBarHidden) {
        [self.navigationController setNavigationBarHidden:NO animated:YES];
    }

    // Always display a left item to leave the view without making changes.
    // This might be a "back", "skip" or "cancel" button depending on the
    // context.
    switch (self.profileViewMode) {
        case ProfileViewMode_AppSettings:
            if (self.hasUnsavedChanges) {
                // If we have a unsaved changes, right item should be a "save" button.
                UIBarButtonItem *saveButton =
                    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                  target:self
                                                                  action:@selector(updatePressed)];
                SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, saveButton);
                self.navigationItem.rightBarButtonItem = saveButton;
            } else {
                self.navigationItem.rightBarButtonItem = nil;
            }
            break;
        case ProfileViewMode_Registration:
            self.navigationItem.hidesBackButton = YES;
            self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
                initWithTitle:NSLocalizedString(@"NAVIGATION_ITEM_SKIP_BUTTON", @"A button to skip a view.")
                        style:UIBarButtonItemStylePlain
                       target:self
                       action:@selector(backOrSkipButtonPressed)];
            break;
    }

    if (self.hasUnsavedChanges) {
        self.saveButton.enabled = YES;
        [self.saveButton setBackgroundColorsWithUpColor:[UIColor ows_signalBrandBlueColor]];
    } else {
        self.saveButton.enabled = NO;
        [self.saveButton
            setBackgroundColorsWithUpColor:[[UIColor ows_signalBrandBlueColor] blendWithColor:Theme.backgroundColor
                                                                                        alpha:0.5f]];
    }
}

- (void)updatePressed
{
    [self updateProfile];
}

- (void)updateProfile
{
    __weak ProfileViewController *weakSelf = self;

    [self.profileNameTextField acceptAutocorrectSuggestion];

    NSString *normalizedProfileName = [self normalizedProfileName];
    if ([OWSProfileManager.sharedManager isProfileNameTooLong:normalizedProfileName]) {
        [OWSAlerts
            showErrorAlertWithMessage:NSLocalizedString(@"PROFILE_VIEW_ERROR_PROFILE_NAME_TOO_LONG",
                                          @"Error message shown when user tries to update profile with a profile name "
                                          @"that is too long.")];
        return;
    }

    // Show an activity indicator to block the UI during the profile upload.
    [ModalActivityIndicatorViewController
        presentFromViewController:self
                        canCancel:NO
                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                      [OWSProfileManager.sharedManager updateLocalProfileName:normalizedProfileName
                          avatarImage:weakSelf.avatar
                          success:^{
                              dispatch_async(dispatch_get_main_queue(), ^{
                                  [modalActivityIndicator dismissWithCompletion:^{
                                      [weakSelf updateProfileCompleted];
                                  }];
                              });
                          }
                          failure:^{
                              dispatch_async(dispatch_get_main_queue(), ^{
                                  [modalActivityIndicator dismissWithCompletion:^{
                                      [OWSAlerts showErrorAlertWithMessage:NSLocalizedString(
                                                                               @"PROFILE_VIEW_ERROR_UPDATE_FAILED",
                                                                               @"Error message shown when a "
                                                                               @"profile update fails.")];
                                  }];
                              });
                          }];
                  }];
}

- (NSString *)normalizedProfileName
{
    return [self.profileNameTextField.text ows_stripped];
}

- (void)updateProfileCompleted
{
    OWSLogVerbose(@"");

    [self profileCompletedOrSkipped];
}

- (void)profileCompletedOrSkipped
{
    OWSLogVerbose(@"");

    // Dismiss this view.
    switch (self.profileViewMode) {
        case ProfileViewMode_AppSettings:
            [self.navigationController popViewControllerAnimated:YES];
            break;
        case ProfileViewMode_Registration:
            [self showPinCreation];
            break;
    }
}

- (void)showHomeView
{
    OWSAssertIsOnMainThread();
    OWSLogVerbose(@"");

    [SignalApp.sharedApp showHomeView];
}

- (void)showPinCreation
{
    OWSAssertIsOnMainThread();
    OWSLogVerbose(@"");

    // If the user already has a pin, or the pins for all feature is disabled, just go home
    if ([OWS2FAManager sharedManager].is2FAEnabled || !SSKFeatureFlags.pinsForEveryone) {
        return [self showHomeView];
    }

    __weak ProfileViewController *weakSelf = self;
    OWSPinSetupViewController *vc = [[OWSPinSetupViewController alloc] initWithCompletionHandler:^{
        [weakSelf showHomeView];
    }];

    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)editingRange
                replacementString:(NSString *)insertionText
{
    // TODO: Possibly filter invalid input.
    return [TextFieldHelper textField:textField
        shouldChangeCharactersInRange:editingRange
                    replacementString:insertionText
                            byteLimit:kOWSProfileManager_NameDataLength];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self.profileNameTextField resignFirstResponder];
    return NO;
}

- (void)textFieldDidChange:(id)sender
{
    self.hasUnsavedChanges = YES;

    // TODO: Update length warning.
}

#pragma mark - Avatar

- (void)setAvatar:(nullable UIImage *)avatar
{
    OWSAssertIsOnMainThread();

    _avatar = avatar;

    self.hasUnsavedChanges = YES;

    [self updateAvatarView];
}

- (NSUInteger)avatarSize
{
    return 96;
}

- (void)updateAvatarView
{
    self.avatarView.image = (self.avatar
            ?: [[[OWSContactAvatarBuilder alloc] initForLocalUserWithDiameter:self.avatarSize] buildDefaultImage]);
}

- (void)updateUsername
{
    NSString *_Nullable username = [OWSProfileManager.sharedManager localUsername];
    if (username) {
        self.usernameLabel.text = [CommonFormats formatUsername:username];
        self.usernameLabel.textColor = Theme.primaryColor;
    } else {
        self.usernameLabel.text = NSLocalizedString(@"PROFILE_VIEW_CREATE_USERNAME",
            @"A string indicating that the user can create a username on the profile view.");
        self.usernameLabel.textColor = UIColor.ows_materialBlueColor;
    }
}

- (void)profileNameRowTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self.profileNameTextField becomeFirstResponder];
    }
}

- (void)usernameRowTapped:(UIGestureRecognizer *)sender
{
    UIViewController *usernameVC = [UsernameViewController new];
    [self presentViewController:[[OWSNavigationController alloc] initWithRootViewController:usernameVC]
                       animated:YES
                     completion:nil];
}

- (void)avatarViewTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self avatarTapped];
    }
}

- (void)infoRowTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        SFSafariViewController *safariVC = [[SFSafariViewController alloc]
            initWithURL:[NSURL URLWithString:@"https://support.signal.org/hc/en-us/articles/115001110511"]];
        [self presentViewController:safariVC animated:YES completion:nil];
    }
}

- (void)saveButtonPressed
{
    [self updatePressed];
}

#pragma mark - AvatarViewHelperDelegate

+ (BOOL)shouldDisplayProfileViewOnLaunch
{
    // Only nag until the user sets a profile _name_.  Profile names are
    // recommended; profile avatars are optional.
    if ([OWSProfileManager sharedManager].localProfileName.length > 0) {
        return NO;
    }

    NSTimeInterval kProfileNagFrequency = kDayInterval * 30;
    __block NSDate *_Nullable lastPresentedDate;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        lastPresentedDate =
            [ProfileViewController.keyValueStore getDate:kProfileView_LastPresentedDate transaction:transaction];
    }];

    return (!lastPresentedDate || fabs([lastPresentedDate timeIntervalSinceNow]) > kProfileNagFrequency);
}

+ (void)presentForAppSettings:(UINavigationController *)navigationController
{
    OWSAssertDebug(navigationController);
    OWSAssertDebug([navigationController isKindOfClass:[OWSNavigationController class]]);

    ProfileViewController *vc = [[ProfileViewController alloc] initWithMode:ProfileViewMode_AppSettings];
    [navigationController pushViewController:vc animated:YES];
}

+ (void)presentForRegistration:(UINavigationController *)navigationController
{
    OWSAssertDebug(navigationController);
    OWSAssertDebug([navigationController isKindOfClass:[OWSNavigationController class]]);

    ProfileViewController *vc = [[ProfileViewController alloc] initWithMode:ProfileViewMode_Registration];
    [navigationController pushViewController:vc animated:YES];
}

#pragma mark - AvatarViewHelperDelegate

- (nullable NSString *)avatarActionSheetTitle
{
    return NSLocalizedString(
        @"PROFILE_VIEW_AVATAR_ACTIONSHEET_TITLE", @"Action Sheet title prompting the user for a profile avatar");
}

- (void)avatarDidChange:(UIImage *)image
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(image);

    self.avatar = [image resizedImageToFillPixelSize:CGSizeMake(kOWSProfileManager_MaxAvatarDiameter,
                                                         kOWSProfileManager_MaxAvatarDiameter)];
}

- (UIViewController *)fromViewController
{
    return self;
}

- (BOOL)hasClearAvatarAction
{
    return YES;
}

- (NSString *)clearAvatarActionLabel
{
    return NSLocalizedString(@"PROFILE_VIEW_CLEAR_AVATAR", @"Label for action that clear's the user's profile avatar");
}

- (void)clearAvatar
{
    self.avatar = nil;
}

#pragma mark - OWSNavigationView

- (BOOL)shouldCancelNavigationBack
{
    BOOL result = self.hasUnsavedChanges;
    if (result) {
        [self backOrSkipButtonPressed];
    }
    return result;
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return (self.profileViewMode == ProfileViewMode_Registration ? UIInterfaceOrientationMaskPortrait
                                                                 : UIInterfaceOrientationMaskAllButUpsideDown);
}

@end

NS_ASSUME_NONNULL_END
