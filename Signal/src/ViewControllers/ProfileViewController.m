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
#import <SignalMessaging/OWSNavigationController.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/NSString+SSK.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ProfileViewMode) {
    ProfileViewMode_AppSettings = 0,
    ProfileViewMode_Registration,
    ProfileViewMode_UpgradeOrNag,
};

NSString *const kProfileView_Collection = @"kProfileView_Collection";
NSString *const kProfileView_LastPresentedDate = @"kProfileView_LastPresentedDate";

@interface ProfileViewController () <UITextFieldDelegate, AvatarViewHelperDelegate, OWSNavigationView>

@property (nonatomic, readonly) AvatarViewHelper *avatarViewHelper;

@property (nonatomic) UITextField *nameTextField;

@property (nonatomic) AvatarImageView *avatarView;

@property (nonatomic) UIImageView *cameraImageView;

@property (nonatomic) OWSFlatButton *saveButton;

@property (nonatomic, nullable) UIImage *avatar;

@property (nonatomic) BOOL hasUnsavedChanges;

@property (nonatomic) ProfileViewMode profileViewMode;

@end

#pragma mark -

@implementation ProfileViewController

- (instancetype)initWithMode:(ProfileViewMode)profileViewMode
{
    self = [super init];

    if (!self) {
        return self;
    }

    self.profileViewMode = profileViewMode;

    // Use the OWSPrimaryStorage.dbReadWriteConnection for consistency with the reads below.
    [[[OWSPrimaryStorage sharedManager] dbReadWriteConnection] setDate:[NSDate new]
                                                                forKey:kProfileView_LastPresentedDate
                                                          inCollection:kProfileView_Collection];

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

    if (self.nameTextField.text.length > 0) {
        self.hasUnsavedChanges = YES;
    }
}

- (void)createViews
{
    self.view.backgroundColor = Theme.offBackgroundColor;

    UIView *contentView = [UIView containerView];
    contentView.backgroundColor = Theme.backgroundColor;
    [self.view addSubview:contentView];
    [contentView autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [contentView autoPinWidthToSuperview];

    const CGFloat fontSizePoints = ScaleFromIPhone5To7Plus(16.f, 20.f);
    NSMutableArray<UIView *> *rows = [NSMutableArray new];

    // Name

    UIView *nameRow = [UIView containerView];
    nameRow.userInteractionEnabled = YES;
    [nameRow
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(nameRowTapped:)]];
    nameRow.accessibilityIdentifier = SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, @"nameRow");
    [rows addObject:nameRow];

    UILabel *nameLabel = [UILabel new];
    nameLabel.text = NSLocalizedString(
        @"PROFILE_VIEW_PROFILE_NAME_FIELD", @"Label for the profile name field of the profile view.");
    nameLabel.textColor = Theme.primaryColor;
    nameLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
    [nameRow addSubview:nameLabel];
    [nameLabel autoPinLeadingToSuperviewMargin];
    [nameLabel autoPinHeightToSuperviewWithMargin:5.f];

    UITextField *nameTextField;
    if (UIDevice.currentDevice.isShorterThanIPhone5) {
        nameTextField = [DismissableTextField new];
    } else {
        nameTextField = [OWSTextField new];
    }
    _nameTextField = nameTextField;
    nameTextField.font = [UIFont ows_mediumFontWithSize:18.f];
    nameTextField.textColor = [UIColor ows_materialBlueColor];
    nameTextField.placeholder = NSLocalizedString(
        @"PROFILE_VIEW_NAME_DEFAULT_TEXT", @"Default text for the profile name field of the profile view.");
    nameTextField.delegate = self;
    nameTextField.text = [OWSProfileManager.sharedManager localProfileName];
    nameTextField.textAlignment = NSTextAlignmentRight;
    nameTextField.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, nameTextField);
    [nameTextField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    [nameRow addSubview:nameTextField];
    [nameTextField autoPinLeadingToTrailingEdgeOfView:nameLabel offset:10.f];
    [nameTextField autoPinTrailingToSuperviewMargin];
    [nameTextField autoVCenterInSuperview];

    // Avatar

    UIView *avatarRow = [UIView containerView];
    avatarRow.userInteractionEnabled = YES;
    [avatarRow
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarRowTapped:)]];
    avatarRow.accessibilityIdentifier = SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, @"avatarRow");
    [rows addObject:avatarRow];

    UILabel *avatarLabel = [UILabel new];
    avatarLabel.text = NSLocalizedString(
        @"PROFILE_VIEW_PROFILE_AVATAR_FIELD", @"Label for the profile avatar field of the profile view.");
    avatarLabel.textColor = Theme.primaryColor;
    avatarLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
    [avatarRow addSubview:avatarLabel];
    [avatarLabel autoPinLeadingToSuperviewMargin];
    [avatarLabel autoVCenterInSuperview];

    self.avatarView = [AvatarImageView new];
    self.avatarView.accessibilityIdentifier = SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, @"avatarView");

    UIImage *cameraImage = [UIImage imageNamed:@"settings-avatar-camera"];
    self.cameraImageView = [[UIImageView alloc] initWithImage:cameraImage];
    
    [avatarRow addSubview:self.avatarView];
    [avatarRow addSubview:self.cameraImageView];
    [self updateAvatarView];
    [self.avatarView autoPinTrailingToSuperviewMargin];
    [self.avatarView autoPinLeadingToTrailingEdgeOfView:avatarLabel offset:10.f];
    const CGFloat kAvatarVMargin = 4.f;
    [self.avatarView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:kAvatarVMargin];
    [self.avatarView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:kAvatarVMargin];
    [self.avatarView autoSetDimension:ALDimensionWidth toSize:self.avatarSize];
    [self.avatarView autoSetDimension:ALDimensionHeight toSize:self.avatarSize];
    [self.cameraImageView autoPinTrailingToEdgeOfView:self.avatarView];
    [self.cameraImageView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.avatarView];

    // Information

    UIView *infoRow = [UIView containerView];
    infoRow.userInteractionEnabled = YES;
    [infoRow
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(infoRowTapped:)]];
    infoRow.accessibilityIdentifier = SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, @"infoRow");
    [rows addObject:infoRow];

    UILabel *infoLabel = [UILabel new];
    infoLabel.textColor = Theme.secondaryColor;
    infoLabel.font = [UIFont ows_regularFontWithSize:11.f];
    infoLabel.textAlignment = NSTextAlignmentCenter;
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
                                             NSUnderlineStyleAttributeName :
                                                 @(NSUnderlineStyleSingle | NSUnderlinePatternSolid),
                                             NSForegroundColorAttributeName : [UIColor ows_materialBlueColor],
                                         }]];
    infoLabel.attributedText = text;
    infoLabel.numberOfLines = 0;
    infoLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [infoRow addSubview:infoLabel];
    [infoLabel autoPinLeadingToSuperviewMargin];
    [infoLabel autoPinTrailingToSuperviewMargin];
    [infoLabel autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:10.f];
    [infoLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:10.f];

    // Big Button

    if (self.profileViewMode == ProfileViewMode_Registration || self.profileViewMode == ProfileViewMode_UpgradeOrNag) {
        UIView *buttonRow = [UIView containerView];
        [rows addObject:buttonRow];

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
        [saveButton autoPinLeadingAndTrailingToSuperviewMargin];
        [saveButton autoPinHeightToSuperview];
        [saveButton autoSetDimension:ALDimensionHeight toSize:47.f];
    }

    // Row Layout

    UIView *_Nullable lastRow = nil;
    for (UIView *row in rows) {
        [contentView addSubview:row];
        if (lastRow) {
            [row autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastRow withOffset:5.f];
        } else {
            [row autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:15.f];
        }
        [row autoPinLeadingToSuperviewMarginWithInset:18.f];
        [row autoPinTrailingToSuperviewMarginWithInset:18.f];
        lastRow = row;

        if (lastRow == nameRow || lastRow == avatarRow) {
            UIView *separator = [UIView containerView];
            separator.backgroundColor = Theme.cellSeparatorColor;
            [contentView addSubview:separator];
            [separator autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastRow withOffset:5.f];
            [separator autoPinLeadingToSuperviewMarginWithInset:18.f];
            [separator autoPinTrailingToSuperviewMarginWithInset:18.f];
            [separator autoSetDimension:ALDimensionHeight toSize:CGHairlineWidth()];
            lastRow = separator;
        }
    }
    [lastRow autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:10.f];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self.nameTextField becomeFirstResponder];
}

#pragma mark - Event Handling

- (void)backOrSkipButtonPressed
{
    [self leaveViewCheckingForUnsavedChanges];
}

- (void)leaveViewCheckingForUnsavedChanges
{
    [self.nameTextField resignFirstResponder];

    if (!self.hasUnsavedChanges) {
        // If user made no changes, return to conversation settings view.
        [self profileCompletedOrSkipped];
        return;
    }
 
    __weak ProfileViewController *weakSelf = self;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:
            NSLocalizedString(@"NEW_GROUP_VIEW_UNSAVED_CHANGES_TITLE",
                @"The alert title if user tries to exit the new group view without saving changes.")
                         message:
                             NSLocalizedString(@"NEW_GROUP_VIEW_UNSAVED_CHANGES_MESSAGE",
                                 @"The alert message if user tries to exit the new group view without saving changes.")
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *discardAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"ALERT_DISCARD_BUTTON",
                                           @"The label for the 'discard' button in alerts and action sheets.")
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *action) {
                                   [weakSelf profileCompletedOrSkipped];
                               }];
    discardAction.accessibilityIdentifier = SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, @"discard");
    [alert addAction:discardAction];

    [alert addAction:[OWSAlerts cancelAction]];
    [self presentAlert:alert];
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
        case ProfileViewMode_UpgradeOrNag:
        case ProfileViewMode_Registration:
            self.navigationItem.hidesBackButton = YES;
            self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
                initWithTitle:NSLocalizedString(@"NAVIGATION_ITEM_SKIP_BUTTON", @"A button to skip a view.")
                        style:UIBarButtonItemStylePlain
                       target:self
                       action:@selector(backOrSkipButtonPressed)];
            break;
    }

    // The save button is only used in "registration" and "upgrade or nag" modes.
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
    return [self.nameTextField.text ows_stripped];
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
            [self showHomeView];
            break;
        case ProfileViewMode_UpgradeOrNag:
            [self dismissViewControllerAnimated:YES completion:nil];
            break;
    }
}

- (void)showHomeView
{
    OWSAssertIsOnMainThread();
    OWSLogVerbose(@"");

    [SignalApp.sharedApp showHomeView];
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
    [self updateProfile];
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
    return 48;
}

- (void)updateAvatarView
{
    self.avatarView.image = (self.avatar
            ?: [[[OWSContactAvatarBuilder alloc] initForLocalUserWithDiameter:self.avatarSize] buildDefaultImage]);
    self.cameraImageView.hidden = self.avatar != nil;
}

- (void)nameRowTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self.nameTextField becomeFirstResponder];
    }
}

- (void)avatarRowTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self avatarTapped];
    }
}

- (void)infoRowTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [UIApplication.sharedApplication
            openURL:[NSURL URLWithString:@"https://support.signal.org/hc/en-us/articles/115001110511"]];
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

    // Use the OWSPrimaryStorage.dbReadWriteConnection for consistency with the writes above.
    NSTimeInterval kProfileNagFrequency = kDayInterval * 30;
    NSDate *_Nullable lastPresentedDate =
        [[[OWSPrimaryStorage sharedManager] dbReadWriteConnection] dateForKey:kProfileView_LastPresentedDate
                                                                 inCollection:kProfileView_Collection];
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

+ (void)presentForUpgradeOrNag:(HomeViewController *)fromViewController
{
    OWSAssertDebug(fromViewController);

    ProfileViewController *vc = [[ProfileViewController alloc] initWithMode:ProfileViewMode_UpgradeOrNag];
    OWSNavigationController *navigationController = [[OWSNavigationController alloc] initWithRootViewController:vc];
    [fromViewController presentViewController:navigationController animated:YES completion:nil];
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
                                                                 : DefaultUIInterfaceOrientationMask());
}

@end

NS_ASSUME_NONNULL_END
