//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ProfileViewController.h"
#import "AppDelegate.h"
#import "AvatarViewHelper.h"
#import "OWSNavigationController.h"
#import "OWSProfileManager.h"
#import "Signal-Swift.h"
#import "SignalsNavigationController.h"
#import "SignalsViewController.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "UIViewController+OWS.h"
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/TSStorageManager.h>

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

@property (nonatomic) UIButton *saveButton;

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

    // Use the TSStorageManager.dbReadWriteConnection for consistency with the reads below.
    [[[TSStorageManager sharedManager] dbReadWriteConnection] setDate:[NSDate new]
                                                               forKey:kProfileView_LastPresentedDate
                                                         inCollection:kProfileView_Collection];

    return self;
}

- (void)loadView
{
    [super loadView];

    [self.navigationController.navigationBar setTranslucent:NO];
    self.title = NSLocalizedString(@"PROFILE_VIEW_TITLE", @"Title for the profile view.");

    _avatarViewHelper = [AvatarViewHelper new];
    _avatarViewHelper.delegate = self;

    _avatar = [OWSProfileManager.sharedManager localProfileAvatarImage];

    [self createViews];
    [self updateNavigationItem];
}

- (void)createViews
{
    self.view.backgroundColor = [UIColor colorWithRGBHex:0xefeff4];

    UIView *contentView = [UIView containerView];
    contentView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:contentView];
    [contentView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [contentView autoPinWidthToSuperview];

    const CGFloat fontSizePoints = ScaleFromIPhone5To7Plus(16.f, 20.f);
    NSMutableArray<UIView *> *rows = [NSMutableArray new];

    // Name

    UIView *nameRow = [UIView containerView];
    nameRow.userInteractionEnabled = YES;
    [nameRow
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(nameRowTapped:)]];
    [rows addObject:nameRow];

    UILabel *nameLabel = [UILabel new];
    nameLabel.text = NSLocalizedString(
        @"PROFILE_VIEW_PROFILE_NAME_FIELD", @"Label for the profile name field of the profile view.");
    nameLabel.textColor = [UIColor blackColor];
    nameLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
    [nameRow addSubview:nameLabel];
    [nameLabel autoPinLeadingToSuperView];
    [nameLabel autoPinHeightToSuperviewWithMargin:5.f];

    UITextField *nameTextField = [UITextField new];
    _nameTextField = nameTextField;
    nameTextField.font = [UIFont ows_mediumFontWithSize:18.f];
    nameTextField.textColor = [UIColor ows_materialBlueColor];
    nameTextField.placeholder = NSLocalizedString(
        @"PROFILE_VIEW_NAME_DEFAULT_TEXT", @"Default text for the profile name field of the profile view.");
    nameTextField.delegate = self;
    nameTextField.text = [OWSProfileManager.sharedManager localProfileName];
    nameTextField.textAlignment = NSTextAlignmentRight;
    nameTextField.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
    [nameTextField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    [nameRow addSubview:nameTextField];
    [nameTextField autoPinLeadingToTrailingOfView:nameLabel margin:10.f];
    [nameTextField autoPinTrailingToSuperView];
    [nameTextField autoVCenterInSuperview];

    // Avatar

    UIView *avatarRow = [UIView containerView];
    avatarRow.userInteractionEnabled = YES;
    [avatarRow
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarRowTapped:)]];
    [rows addObject:avatarRow];

    UILabel *avatarLabel = [UILabel new];
    avatarLabel.text = NSLocalizedString(
        @"PROFILE_VIEW_PROFILE_AVATAR_FIELD", @"Label for the profile avatar field of the profile view.");
    avatarLabel.textColor = [UIColor blackColor];
    avatarLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
    [avatarRow addSubview:avatarLabel];
    [avatarLabel autoPinLeadingToSuperView];
    [avatarLabel autoVCenterInSuperview];

    self.avatarView = [AvatarImageView new];

    UIImage *cameraImage = [UIImage imageNamed:@"settings-avatar-camera"];
    cameraImage = [cameraImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.cameraImageView = [[UIImageView alloc] initWithImage:cameraImage];
    self.cameraImageView.tintColor = [UIColor ows_materialBlueColor];

    [avatarRow addSubview:self.avatarView];
    [avatarRow addSubview:self.cameraImageView];
    [self updateAvatarView];
    [self.avatarView autoPinTrailingToSuperView];
    [self.avatarView autoPinLeadingToTrailingOfView:avatarLabel margin:10.f];
    const CGFloat kAvatarSizePoints = 50.f;
    const CGFloat kAvatarVMargin = 4.f;
    [self.avatarView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:kAvatarVMargin];
    [self.avatarView autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:kAvatarVMargin];
    [self.avatarView autoSetDimension:ALDimensionWidth toSize:kAvatarSizePoints];
    [self.avatarView autoSetDimension:ALDimensionHeight toSize:kAvatarSizePoints];
    [self.cameraImageView autoPinTrailingToView:self.avatarView];
    [self.cameraImageView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.avatarView];

    // Information

    UIView *infoRow = [UIView containerView];
    infoRow.userInteractionEnabled = YES;
    [infoRow
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(infoRowTapped:)]];
    [rows addObject:infoRow];

    UILabel *infoLabel = [UILabel new];
    infoLabel.textColor = [UIColor ows_darkGrayColor];
    infoLabel.font = [UIFont ows_footnoteFont];
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
    [infoLabel autoPinLeadingToSuperView];
    [infoLabel autoPinTrailingToSuperView];
    [infoLabel autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:10.f];
    [infoLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:10.f];

    // Big Button

    if (self.profileViewMode == ProfileViewMode_Registration || self.profileViewMode == ProfileViewMode_UpgradeOrNag) {
        UIView *buttonRow = [UIView containerView];
        [rows addObject:buttonRow];

        UIButton *saveButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.saveButton = saveButton;
        saveButton.backgroundColor = [UIColor ows_signalBrandBlueColor];
        [saveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        saveButton.titleLabel.font = [UIFont ows_boldFontWithSize:fontSizePoints];
        [saveButton setTitle:NSLocalizedString(
                                 @"PROFILE_VIEW_SAVE_BUTTON", @"Button to save the profile view in the profile view.")
                    forState:UIControlStateNormal];
        [saveButton setContentHorizontalAlignment:UIControlContentHorizontalAlignmentCenter];
        [saveButton setContentVerticalAlignment:UIControlContentVerticalAlignmentCenter];
        [buttonRow addSubview:saveButton];
        [saveButton autoPinLeadingAndTrailingToSuperview];
        [saveButton autoPinHeightToSuperview];
        [saveButton autoSetDimension:ALDimensionHeight toSize:47.f];
        [saveButton addTarget:self action:@selector(saveButtonPressed) forControlEvents:UIControlEventTouchUpInside];
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
        [row autoPinLeadingToSuperViewWithMargin:18.f];
        [row autoPinTrailingToSuperViewWithMargin:18.f];
        lastRow = row;

        if (lastRow == nameRow || lastRow == avatarRow) {
            UIView *separator = [UIView containerView];
            separator.backgroundColor = [UIColor colorWithWhite:0.9f alpha:1.f];
            [contentView addSubview:separator];
            [separator autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastRow withOffset:5.f];
            [separator autoPinLeadingToSuperViewWithMargin:18.f];
            [separator autoPinTrailingToSuperViewWithMargin:18.f];
            [separator autoSetDimension:ALDimensionHeight toSize:1.f];
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

    UIAlertController *controller = [UIAlertController
        alertControllerWithTitle:
            NSLocalizedString(@"NEW_GROUP_VIEW_UNSAVED_CHANGES_TITLE",
                @"The alert title if user tries to exit the new group view without saving changes.")
                         message:
                             NSLocalizedString(@"NEW_GROUP_VIEW_UNSAVED_CHANGES_MESSAGE",
                                 @"The alert message if user tries to exit the new group view without saving changes.")
                  preferredStyle:UIAlertControllerStyleAlert];
    [controller
        addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"ALERT_DISCARD_BUTTON",
                                                     @"The label for the 'discard' button in alerts and action sheets.")
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action) {
                                             [self profileCompletedOrSkipped];
                                         }]];
    [controller addAction:[OWSAlerts cancelAction]];
    [self presentViewController:controller animated:YES completion:nil];
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
                self.navigationItem.rightBarButtonItem =
                    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                  target:self
                                                                  action:@selector(updatePressed)];
            } else {
                self.navigationItem.rightBarButtonItem = nil;
            }
            break;
        case ProfileViewMode_UpgradeOrNag:
            self.navigationItem.leftBarButtonItem =
                [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                              target:self
                                                              action:@selector(backOrSkipButtonPressed)];
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

    // The save button is only used in "registration" and "upgrade or nag" modes.
    if (self.hasUnsavedChanges) {
        self.saveButton.enabled = YES;
        self.saveButton.backgroundColor = [UIColor ows_signalBrandBlueColor];
    } else {
        self.saveButton.enabled = NO;
        self.saveButton.backgroundColor =
            [[UIColor ows_signalBrandBlueColor] blendWithColor:[UIColor whiteColor] alpha:0.5f];
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
        [OWSAlerts showAlertWithTitle:NSLocalizedString(@"ALERT_ERROR_TITLE", @"")
                              message:NSLocalizedString(@"PROFILE_VIEW_ERROR_PROFILE_NAME_TOO_LONG",
                                          @"Error message shown when user tries to update profile with a profile name "
                                          @"that is too long.")];
        return;
    }

    // Show an activity indicator to block the UI during the profile upload.
    UIAlertController *alertController = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"PROFILE_VIEW_SAVING",
                                     @"Alert title that indicates the user's profile view is being saved.")
                         message:nil
                  preferredStyle:UIAlertControllerStyleAlert];

    [self presentViewController:alertController
                       animated:YES
                     completion:^{
                         [OWSProfileManager.sharedManager updateLocalProfileName:normalizedProfileName
                             avatarImage:self.avatar
                             success:^{
                                 [alertController dismissViewControllerAnimated:NO
                                                                     completion:^{
                                                                         [weakSelf updateProfileCompleted];
                                                                     }];
                             }
                             failure:^{
                                 [alertController
                                     dismissViewControllerAnimated:NO
                                                        completion:^{
                                                            [OWSAlerts
                                                                showAlertWithTitle:NSLocalizedString(
                                                                                       @"ALERT_ERROR_TITLE", @"")
                                                                           message:
                                                                               NSLocalizedString(
                                                                                   @"PROFILE_VIEW_ERROR_UPDATE_FAILED",
                                                                                   @"Error message shown when a "
                                                                                   @"profile update fails.")];
                                                        }];
                             }];
                     }];
}

- (NSString *)normalizedProfileName
{
    return [self.nameTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (void)updateProfileCompleted
{
    [self profileCompletedOrSkipped];
}

- (void)profileCompletedOrSkipped
{
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
    SignalsViewController *homeView = [SignalsViewController new];
    homeView.newlyRegisteredUser = YES;
    SignalsNavigationController *navigationController =
        [[SignalsNavigationController alloc] initWithRootViewController:homeView];
    AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    appDelegate.window.rootViewController = navigationController;
    OWSAssert([navigationController.topViewController isKindOfClass:[SignalsViewController class]]);
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
{
    // TODO: Possibly filter invalid input.
    // TODO: Possibly prevent user from typing overlong name.
    return YES;
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
    OWSAssert([NSThread isMainThread]);

    _avatar = avatar;

    self.hasUnsavedChanges = YES;

    [self updateAvatarView];
}

- (void)updateAvatarView
{
    self.avatarView.image = (self.avatar
            ?: [[UIImage imageNamed:@"profile_avatar_default"]
                   imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]);
    self.avatarView.tintColor = (self.avatar ? nil : [UIColor colorWithRGBHex:0x888888]);
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
            openURL:[NSURL URLWithString:@"https://support.whispersystems.org/hc/en-us/articles/115001110511"]];
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

    // Use the TSStorageManager.dbReadWriteConnection for consistency with the writes above.
    NSTimeInterval kProfileNagFrequency = kDayInterval * 30;
    NSDate *_Nullable lastPresentedDate =
        [[[TSStorageManager sharedManager] dbReadWriteConnection] dateForKey:kProfileView_LastPresentedDate
                                                                inCollection:kProfileView_Collection];
    return (!lastPresentedDate || fabs([lastPresentedDate timeIntervalSinceNow]) > kProfileNagFrequency);
}

+ (void)presentForAppSettings:(UINavigationController *)navigationController
{
    OWSAssert(navigationController);
    OWSAssert([navigationController isKindOfClass:[OWSNavigationController class]]);

    ProfileViewController *vc = [[ProfileViewController alloc] initWithMode:ProfileViewMode_AppSettings];
    [navigationController pushViewController:vc animated:YES];
}

+ (void)presentForRegistration:(UINavigationController *)navigationController
{
    OWSAssert(navigationController);
    OWSAssert([navigationController isKindOfClass:[OWSNavigationController class]]);

    ProfileViewController *vc = [[ProfileViewController alloc] initWithMode:ProfileViewMode_Registration];
    [navigationController pushViewController:vc animated:YES];
}

+ (void)presentForUpgradeOrNag:(SignalsViewController *)presentingController
{
    OWSAssert(presentingController);

    ProfileViewController *vc = [[ProfileViewController alloc] initWithMode:ProfileViewMode_UpgradeOrNag];
    OWSNavigationController *navigationController = [[OWSNavigationController alloc] initWithRootViewController:vc];
    [presentingController presentTopLevelModalViewController:navigationController
                                            animateDismissal:YES
                                         animatePresentation:YES];
}

#pragma mark - AvatarViewHelperDelegate

- (NSString *)avatarActionSheetTitle
{
    return NSLocalizedString(
        @"PROFILE_VIEW_AVATAR_ACTIONSHEET_TITLE", @"Action Sheet title prompting the user for a profile avatar");
}

- (void)avatarDidChange:(UIImage *)image
{
    OWSAssert(image);

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
