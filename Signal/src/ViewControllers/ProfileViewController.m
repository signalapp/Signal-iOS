//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ProfileViewController.h"
#import "AppDelegate.h"
#import "AvatarViewHelper.h"
#import "ConversationListViewController.h"
#import "OWSNavigationController.h"
#import "Signal-Swift.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/OWSNavigationController.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalMessaging/UIViewController+OWS.h>

@import SafariServices;

NS_ASSUME_NONNULL_BEGIN

NSString *const kProfileView_LastPresentedDate = @"kProfileView_LastPresentedDate";

@interface ProfileViewController () <UITextFieldDelegate, AvatarViewHelperDelegate, OWSNavigationView>

@property (nonatomic, readonly) AvatarViewHelper *avatarViewHelper;

@property (nonatomic) UITextField *givenNameTextField;

@property (nonatomic) UITextField *familyNameTextField;

@property (nonatomic) UILabel *profileNamePreviewLabel;

@property (nonatomic) UILabel *usernameLabel;

@property (nonatomic) AvatarImageView *avatarView;

@property (nonatomic) UIImageView *cameraImageView;

@property (nonatomic) OWSFlatButton *saveButton;

@property (nonatomic, nullable) NSData *avatarData;

@property (nonatomic) BOOL hasUnsavedChanges;

@property (nonatomic) ProfileViewMode profileViewMode;

@property (nonatomic, readonly) void (^completionHandler)(ProfileViewController *);

@end

#pragma mark -

@implementation ProfileViewController

+ (SDSKeyValueStore *)keyValueStore
{
    return [[SDSKeyValueStore alloc] initWithCollection:@"kProfileView_Collection"];
}

- (instancetype)initWithMode:(ProfileViewMode)profileViewMode
           completionHandler:(void (^)(ProfileViewController *))completionHandler
{
    self = [super init];

    if (!self) {
        return self;
    }

    _profileViewMode = profileViewMode;
    _completionHandler = completionHandler;

    DatabaseStorageAsyncWrite(SDSDatabaseStorage.shared, ^(SDSAnyWriteTransaction *transaction) {
        [ProfileViewController.keyValueStore setDate:[NSDate new]
                                                 key:kProfileView_LastPresentedDate
                                         transaction:transaction];
    });

    return self;
}

- (void)loadView
{
    [super loadView];

    self.title = NSLocalizedString(@"PROFILE_VIEW_TITLE", @"Title for the profile view.");

    _avatarViewHelper = [AvatarViewHelper new];
    _avatarViewHelper.delegate = self;

    _avatarData = [OWSProfileManager.shared localProfileAvatarData];

    [self createViews];
    [self updateNavigationItem];

    if (self.profileViewMode == ProfileViewMode_Registration) {
        // mark as dirty if re-registration has content
        if (self.familyNameTextField.text.length > 0 || self.givenNameTextField.text.length > 0
            || self.avatarData != nil) {
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
    [self.avatarView autoSetDimension:ALDimensionWidth toSize:self.avatarSize];
    [self.avatarView autoSetDimension:ALDimensionHeight toSize:self.avatarSize];

    self.cameraImageView = [UIImageView new];
    [self.cameraImageView setTemplateImageName:@"camera-outline-24" tintColor:Theme.secondaryTextAndIconColor];
    [self.cameraImageView autoSetDimensionsToSize:CGSizeMake(32, 32)];
    self.cameraImageView.contentMode = UIViewContentModeCenter;
    self.cameraImageView.backgroundColor = Theme.backgroundColor;
    self.cameraImageView.layer.cornerRadius = 16;
    self.cameraImageView.layer.shadowColor =
        [(Theme.isDarkThemeEnabled ? Theme.darkThemeWashColor : Theme.primaryTextColor) CGColor];
    self.cameraImageView.layer.shadowOffset = CGSizeMake(1, 1);
    self.cameraImageView.layer.shadowOpacity = 0.5;
    self.cameraImageView.layer.shadowRadius = 4;

    [avatarRow addSubview:self.cameraImageView];
    [self.cameraImageView autoPinTrailingToEdgeOfView:self.avatarView];
    [self.cameraImageView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.avatarView];

    self.profileNamePreviewLabel = [UILabel new];
    self.profileNamePreviewLabel.textAlignment = NSTextAlignmentCenter;
    self.profileNamePreviewLabel.textColor = Theme.secondaryTextAndIconColor;
    self.profileNamePreviewLabel.font = UIFont.ows_dynamicTypeSubheadlineClampedFont;
    [avatarRow addSubview:self.profileNamePreviewLabel];
    [self.profileNamePreviewLabel autoPinWidthToSuperviewWithMargin:16];
    [self.profileNamePreviewLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.avatarView withOffset:16];
    [self.profileNamePreviewLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom
                                                   withInset:28
                                                    relation:NSLayoutRelationGreaterThanOrEqual];
    [self.profileNamePreviewLabel autoSetDimension:ALDimensionHeight toSize:16];

    [self updateAvatarView];

    addSeparator(NO);

    // Given Name

    void (^addGivenNameRow)(void) = ^{
        UIStackView *givenNameRow = [UIStackView new];
        givenNameRow.spacing = rowSpacing;
        givenNameRow.layoutMarginsRelativeArrangement = YES;
        givenNameRow.layoutMargins = rowMargins;
        [givenNameRow
            addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(givenNameRowTapped:)]];
        givenNameRow.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"givenNameRow");
        [stackView addArrangedSubview:givenNameRow];

        UILabel *givenNameLabel = [UILabel new];
        givenNameLabel.text = NSLocalizedString(
            @"PROFILE_VIEW_GIVEN_NAME_FIELD", @"Label for the given name field of the profile view.");
        givenNameLabel.textColor = Theme.primaryTextColor;
        givenNameLabel.font = [[UIFont ows_dynamicTypeBodyClampedFont] ows_semibold];
        [givenNameRow addArrangedSubview:givenNameLabel];

        UITextField *givenNameTextField;
        if (UIDevice.currentDevice.isIPhone5OrShorter) {
            givenNameTextField = [DismissableTextField new];
        } else {
            givenNameTextField = [OWSTextField new];
        }
        self.givenNameTextField = givenNameTextField;
        givenNameTextField.returnKeyType = UIReturnKeyNext;
        givenNameTextField.autocorrectionType = UITextAutocorrectionTypeNo;
        givenNameTextField.spellCheckingType = UITextSpellCheckingTypeNo;
        givenNameTextField.font = [UIFont ows_dynamicTypeBodyClampedFont];
        givenNameTextField.textColor = Theme.primaryTextColor;
        givenNameTextField.placeholder = NSLocalizedString(
            @"PROFILE_VIEW_GIVEN_NAME_DEFAULT_TEXT", @"Default text for the given name field of the profile view.");
        givenNameTextField.delegate = self;
        givenNameTextField.text = OWSProfileManager.shared.localGivenName;
        givenNameTextField.textAlignment = NSTextAlignmentRight;
        SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, givenNameTextField);
        [givenNameTextField addTarget:self
                               action:@selector(textFieldDidChange:)
                     forControlEvents:UIControlEventEditingChanged];
        [givenNameRow addArrangedSubview:givenNameTextField];
    };

    // Family Name

    void (^addFamilyNameRow)(void) = ^{
        UIStackView *familyNameRow = [UIStackView new];
        familyNameRow.spacing = rowSpacing;
        familyNameRow.layoutMarginsRelativeArrangement = YES;
        familyNameRow.layoutMargins = rowMargins;
        [familyNameRow
            addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(familyNameRowTapped:)]];
        familyNameRow.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"familyNameRow");
        [stackView addArrangedSubview:familyNameRow];

        UILabel *familyNameLabel = [UILabel new];
        familyNameLabel.text = NSLocalizedString(
            @"PROFILE_VIEW_FAMILY_NAME_FIELD", @"Label for the family name field of the profile view.");
        familyNameLabel.textColor = Theme.primaryTextColor;
        familyNameLabel.font = [[UIFont ows_dynamicTypeBodyClampedFont] ows_semibold];
        [familyNameRow addArrangedSubview:familyNameLabel];

        UITextField *familyNameTextField;
        if (UIDevice.currentDevice.isIPhone5OrShorter) {
            familyNameTextField = [DismissableTextField new];
        } else {
            familyNameTextField = [OWSTextField new];
        }
        self.familyNameTextField = familyNameTextField;
        familyNameTextField.returnKeyType = UIReturnKeyDone;
        familyNameTextField.autocorrectionType = UITextAutocorrectionTypeNo;
        familyNameTextField.spellCheckingType = UITextSpellCheckingTypeNo;
        familyNameTextField.font = [UIFont ows_dynamicTypeBodyClampedFont];
        familyNameTextField.textColor = Theme.primaryTextColor;
        familyNameTextField.placeholder = NSLocalizedString(
            @"PROFILE_VIEW_FAMILY_NAME_DEFAULT_TEXT", @"Default text for the family name field of the profile view.");
        familyNameTextField.delegate = self;
        familyNameTextField.text = OWSProfileManager.shared.localFamilyName;
        familyNameTextField.textAlignment = NSTextAlignmentRight;
        SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, familyNameTextField);
        [familyNameTextField addTarget:self
                                action:@selector(textFieldDidChange:)
                      forControlEvents:UIControlEventEditingChanged];
        [familyNameRow addArrangedSubview:familyNameTextField];
    };

    // For CJKV locales, display family name field first.
    if (NSLocale.currentLocale.isCJKV) {
        addFamilyNameRow();
        addSeparator(YES);
        addGivenNameRow();

    // Otherwise, display given name field first.
    } else {
        addGivenNameRow();
        addSeparator(YES);
        addFamilyNameRow();
    }

    [self updateProfileNamePreview];

    // Username

    if (self.shouldShowUsernameRow) {
        addSeparator(YES);

        UIStackView *usernameRow = [UIStackView new];
        usernameRow.spacing = rowSpacing;
        usernameRow.layoutMarginsRelativeArrangement = YES;
        usernameRow.layoutMargins = rowMargins;
        [usernameRow
            addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(usernameRowTapped:)]];
        usernameRow.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"usernameRow");
        [stackView addArrangedSubview:usernameRow];

        UILabel *usernameTitleLabel = [UILabel new];
        usernameTitleLabel.text
            = NSLocalizedString(@"PROFILE_VIEW_USERNAME_FIELD", @"Label for the username field of the profile view.");
        usernameTitleLabel.textColor = Theme.primaryTextColor;
        usernameTitleLabel.font = [[UIFont ows_dynamicTypeBodyClampedFont] ows_semibold];
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
    infoLabel.textColor = Theme.secondaryTextAndIconColor;
    infoLabel.font = [UIFont ows_dynamicTypeCaption1ClampedFont];
    NSMutableAttributedString *text = [NSMutableAttributedString new];
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:NSLocalizedString(@"PROFILE_VIEW_PROFILE_DESCRIPTION",
                                                        @"Description of the user profile.")
                                         attributes:@{}]];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:@{}]];
    [text appendAttributedString:[[NSAttributedString alloc]
                                     initWithString:CommonStrings.learnMore
                                         attributes:@{
                                             NSUnderlineStyleAttributeName : @(NSUnderlineStyleNone),
                                             NSForegroundColorAttributeName : Theme.accentBlueColor,
                                         }]];
    infoLabel.attributedText = text;
    infoLabel.numberOfLines = 0;
    infoLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [infoRow addSubview:infoLabel];
    [infoLabel autoPinEdgesToSuperviewMargins];

    // Big Button

    switch (self.profileViewMode) {
        case ProfileViewMode_Registration:
        case ProfileViewMode_ExperienceUpgrade: {
            UIView *buttonRow = [UIView new];
            buttonRow.layoutMargins = rowMargins;
            [stackView addArrangedSubview:buttonRow];

            const CGFloat kButtonHeight = 47.f;
            OWSFlatButton *saveButton =
                [OWSFlatButton buttonWithTitle:NSLocalizedString(@"PROFILE_VIEW_SAVE_BUTTON",
                                                   @"Button to save the profile view in the profile view.")
                                          font:[OWSFlatButton fontForHeight:kButtonHeight]
                                    titleColor:[UIColor whiteColor]
                               backgroundColor:UIColor.ows_accentBlueColor
                                        target:self
                                      selector:@selector(saveButtonPressed)];
            SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, saveButton);
            self.saveButton = saveButton;
            [buttonRow addSubview:saveButton];
            [saveButton autoPinEdgesToSuperviewMargins];
            [saveButton autoSetDimension:ALDimensionHeight toSize:47.f];

            break;
        }
        case ProfileViewMode_AppSettings:
            break;
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    switch (self.profileViewMode) {
        case ProfileViewMode_AppSettings:
            break;
        case ProfileViewMode_Registration:
        case ProfileViewMode_ExperienceUpgrade:
            [self.givenNameTextField becomeFirstResponder];
            break;
    }

    [self updateUsername];
}

#pragma mark - Event Handling

- (void)leaveViewCheckingForUnsavedChanges
{
    [self.familyNameTextField resignFirstResponder];
    [self.givenNameTextField resignFirstResponder];

    if (!self.hasUnsavedChanges) {
        // If user made no changes, return to conversation settings view.
        [self profileCompleted];
        return;
    }
 
    __weak ProfileViewController *weakSelf = self;
    [OWSActionSheets showPendingChangesActionSheetWithDiscardAction:^{
        [weakSelf profileCompleted];
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

    BOOL forceSaveButtonEnabled = NO;

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
            self.navigationItem.rightBarButtonItem = nil;

            // During registration, if you have a name pre-populatd we want
            // to enable the save button even if you haven't edited anything.
            if (self.givenNameTextField.text.length > 0) {
                forceSaveButtonEnabled = YES;
            }
            break;
        case ProfileViewMode_ExperienceUpgrade:
            self.navigationItem.rightBarButtonItem = nil;

            // During the experience upgrade, if you have a name we want
            // to enable the save button even if you haven't edited anything.
            if (self.givenNameTextField.text.length > 0) {
                forceSaveButtonEnabled = YES;
            }
            break;
    }

    if (self.hasUnsavedChanges || forceSaveButtonEnabled) {
        self.saveButton.enabled = YES;
        [self.saveButton setBackgroundColorsWithUpColor:UIColor.ows_accentBlueColor];
    } else {
        self.saveButton.enabled = NO;
        [self.saveButton
            setBackgroundColorsWithUpColor:[UIColor.ows_accentBlueColor blendedWithColor:Theme.backgroundColor
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

    NSString *normalizedGivenName = [self normalizedGivenName];
    NSString *normalizedFamilyName = [self normalizedFamilyName];

    if (normalizedGivenName.length <= 0) {
        [OWSActionSheets showErrorAlertWithMessage:
                             NSLocalizedString(@"PROFILE_VIEW_ERROR_GIVEN_NAME_REQUIRED",
                                 @"Error message shown when user tries to update profile without a given name")];
        return;
    }

    if ([OWSProfileManager.shared isProfileNameTooLong:normalizedGivenName]) {
        [OWSActionSheets
            showErrorAlertWithMessage:NSLocalizedString(@"PROFILE_VIEW_ERROR_GIVEN_NAME_TOO_LONG",
                                          @"Error message shown when user tries to update profile with a given name "
                                          @"that is too long.")];
        return;
    }

    if ([OWSProfileManager.shared isProfileNameTooLong:normalizedFamilyName]) {
        [OWSActionSheets
            showErrorAlertWithMessage:NSLocalizedString(@"PROFILE_VIEW_ERROR_FAMILY_NAME_TOO_LONG",
                                          @"Error message shown when user tries to update profile with a family name "
                                          @"that is too long.")];
        return;
    }

    if (!self.reachabilityManager.isReachable) {
        [OWSActionSheets
            showErrorAlertWithMessage:
                NSLocalizedString(@"PROFILE_VIEW_NO_CONNECTION",
                    @"Error shown when the user tries to update their profile when the app is not connected to the "
                    @"internet.")];
        return;
    }

    // Show an activity indicator to block the UI during the profile upload.
    [ModalActivityIndicatorViewController
        presentFromViewController:self
                        canCancel:NO
                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                      [OWSProfileManager updateLocalProfilePromiseObjWithProfileGivenName:normalizedGivenName
                                                                        profileFamilyName:normalizedFamilyName
                                                                        profileAvatarData:weakSelf.avatarData]

                          .then(^{
                              OWSAssertIsOnMainThread();

                              [modalActivityIndicator dismissWithCompletion:^{
                                  [weakSelf updateProfileCompleted];
                              }];
                          })
                          .catch(^(NSError *error) {
                              OWSAssertIsOnMainThread();
                              OWSFailDebug(@"Error: %@", error);

                              [modalActivityIndicator dismissWithCompletion:^{
                                  // Don't show an error alert; the profile update
                                  // is enqueued and will be completed later.
                                  [weakSelf updateProfileCompleted];
                              }];
                          });
                  }];
}

- (NSString *)normalizedGivenName
{
    return [self.givenNameTextField.text ows_stripped];
}

- (NSString *)normalizedFamilyName
{
    return [self.familyNameTextField.text ows_stripped];
}

- (void)updateProfileCompleted
{
    OWSLogVerbose(@"");

    [self profileCompleted];
}

- (void)profileCompleted
{
    OWSLogVerbose(@"");
    self.completionHandler(self);
}

- (void)showConversationSplitView
{
    OWSAssertIsOnMainThread();
    OWSLogVerbose(@"");

    [SignalApp.sharedApp showConversationSplitView];
}

#pragma mark - UITextFieldDelegate

- (UITextField *)firstTextField
{
    return NSLocale.currentLocale.isCJKV ? self.familyNameTextField : self.givenNameTextField;
}

- (UITextField *)secondTextField
{
    return NSLocale.currentLocale.isCJKV ? self.givenNameTextField : self.familyNameTextField;
}

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)editingRange
                replacementString:(NSString *)insertionText
{
    // TODO: Possibly filter invalid input.
    return [TextFieldHelper textField:textField
        shouldChangeCharactersInRange:editingRange
                    replacementString:insertionText.withoutBidiControlCharacters
                            byteLimit:OWSUserProfile.kNameDataLength];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    if (textField == self.firstTextField) {
        [self.secondTextField becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
    }
    return NO;
}

- (void)textFieldDidChange:(id)sender
{
    self.hasUnsavedChanges = YES;

    [self updateProfileNamePreview];

    // TODO: Update length warning.
}

#pragma mark - Avatar

- (void)setAvatarImage:(nullable UIImage *)avatarImage
{
    OWSAssertIsOnMainThread();

    NSData *_Nullable avatarData = nil;
    if (avatarImage != nil) {
        avatarData = [OWSProfileManager avatarDataForAvatarImage:avatarImage];
    }
    self.hasUnsavedChanges = ![NSObject isNullableObject:avatarData equalTo:_avatarData];
    _avatarData = avatarData;

    [self updateAvatarView];
}

- (NSUInteger)avatarSize
{
    return 96;
}

- (void)updateAvatarView
{
    if (self.avatarData != nil) {
        self.avatarView.image = [UIImage imageWithData:self.avatarData];
    } else {
        self.avatarView.image =
            [[[OWSContactAvatarBuilder alloc] initForLocalUserWithDiameter:self.avatarSize] buildDefaultImage];
    }
}

- (void)updateProfileNamePreview
{
    NSPersonNameComponents *components = [NSPersonNameComponents new];
    components.givenName = [self normalizedGivenName];
    components.familyName = [self normalizedFamilyName];

    self.profileNamePreviewLabel.text =
        [NSPersonNameComponentsFormatter localizedStringFromPersonNameComponents:components style:0 options:0];
}

- (void)updateUsername
{
    NSString *_Nullable username = [OWSProfileManager.shared localUsername];
    if (username) {
        self.usernameLabel.text = [CommonFormats formatUsername:username];
        self.usernameLabel.textColor = Theme.primaryTextColor;
    } else {
        self.usernameLabel.text = NSLocalizedString(@"PROFILE_VIEW_CREATE_USERNAME",
            @"A string indicating that the user can create a username on the profile view.");
        self.usernameLabel.textColor = Theme.accentBlueColor;
    }
}

- (void)givenNameRowTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self.givenNameTextField becomeFirstResponder];
    }
}

- (void)familyNameRowTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self.familyNameTextField becomeFirstResponder];
    }
}

- (void)usernameRowTapped:(UIGestureRecognizer *)sender
{
    UsernameViewController *usernameVC = [UsernameViewController new];
    if (self.profileViewMode == ProfileViewMode_Registration) {
        usernameVC.modalPresentation = YES;
        [self presentFormSheetViewController:[[OWSNavigationController alloc] initWithRootViewController:usernameVC]
                                    animated:YES
                                  completion:nil];
    } else {
        [self.navigationController pushViewController:usernameVC animated:YES];
    }
}

- (BOOL)shouldShowUsernameRow
{
    switch (self.profileViewMode) {
        case ProfileViewMode_ExperienceUpgrade:
        case ProfileViewMode_Registration:
            return false;
        case ProfileViewMode_AppSettings:
            return RemoteConfig.usernames;
    }
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
            initWithURL:[NSURL URLWithString:@"https://support.signal.org/hc/articles/360007459591"]];
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
    if ([OWSProfileManager shared].localGivenName.length > 0) {
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

    [self setAvatarImage:[image resizedImageToFillPixelSize:CGSizeMake(kOWSProfileManager_MaxAvatarDiameter,
                                                                kOWSProfileManager_MaxAvatarDiameter)]];
}

- (UIViewController *)fromViewController
{
    return self;
}

- (BOOL)hasClearAvatarAction
{
    return self.avatarData != nil;
}

- (NSString *)clearAvatarActionLabel
{
    return NSLocalizedString(@"PROFILE_VIEW_CLEAR_AVATAR", @"Label for action that clear's the user's profile avatar");
}

- (void)clearAvatar
{
    [self setAvatarImage:nil];
}

#pragma mark - OWSNavigationView

- (BOOL)shouldCancelNavigationBack
{
    BOOL result = self.hasUnsavedChanges;
    if (result) {
        [self leaveViewCheckingForUnsavedChanges];
    }
    return result;
}

#pragma mark - Orientation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if (UIDevice.currentDevice.isIPad) {
        return UIInterfaceOrientationMaskAll;
    }

    return (self.profileViewMode == ProfileViewMode_Registration ? UIInterfaceOrientationMaskPortrait
                                                                 : UIInterfaceOrientationMaskAllButUpsideDown);
}

@end

NS_ASSUME_NONNULL_END
