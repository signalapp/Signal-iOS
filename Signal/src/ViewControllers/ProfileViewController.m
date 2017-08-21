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

    self.view.backgroundColor = [UIColor whiteColor];
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
    _nameTextField = [UITextField new];
    _nameTextField.font = [UIFont ows_mediumFontWithSize:18.f];
    _nameTextField.textColor = [UIColor ows_materialBlueColor];
    _nameTextField.placeholder = NSLocalizedString(
        @"PROFILE_VIEW_NAME_DEFAULT_TEXT", @"Default text for the profile name field of the profile view.");
    _nameTextField.delegate = self;
    _nameTextField.text = [OWSProfileManager.sharedManager localProfileName];
    [_nameTextField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];

    _avatarView = [AvatarImageView new];

    UIImage *cameraImage = [UIImage imageNamed:@"settings-avatar-camera"];
    cameraImage = [cameraImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _cameraImageView = [[UIImageView alloc] initWithImage:cameraImage];
    _cameraImageView.tintColor = [UIColor ows_materialBlueColor];

    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak ProfileViewController *weakSelf = self;

    // Profile Avatar
    OWSTableSection *section = [OWSTableSection new];
    const CGFloat fontSizePoints = ScaleFromIPhone5To7Plus(16.f, 20.f);
    [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.preservesSuperviewLayoutMargins = YES;
        cell.contentView.preservesSuperviewLayoutMargins = YES;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UILabel *fieldLabel = [UILabel new];
        fieldLabel.text = NSLocalizedString(
            @"PROFILE_VIEW_PROFILE_NAME_FIELD", @"Label for the profile name field of the profile view.");
        fieldLabel.textColor = [UIColor blackColor];
        fieldLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
        [cell.contentView addSubview:fieldLabel];
        [fieldLabel autoPinLeadingToSuperView];
        [fieldLabel autoVCenterInSuperview];

        UITextField *nameTextField = weakSelf.nameTextField;
        nameTextField.textAlignment = NSTextAlignmentRight;
        nameTextField.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
        [cell.contentView addSubview:nameTextField];
        [nameTextField autoPinLeadingToTrailingOfView:fieldLabel margin:10.f];
        [nameTextField autoPinTrailingToSuperView];
        [nameTextField autoVCenterInSuperview];

        return cell;
    }
                         actionBlock:^{
                             [weakSelf.nameTextField becomeFirstResponder];
                         }]];

    const CGFloat kAvatarSizePoints = 50.f;
    const CGFloat kAvatarVMargin = 4.f;
    CGFloat avatarCellHeight = round(kAvatarSizePoints + kAvatarVMargin * 2);
    [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.preservesSuperviewLayoutMargins = YES;
        cell.contentView.preservesSuperviewLayoutMargins = YES;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UILabel *fieldLabel = [UILabel new];
        fieldLabel.text = NSLocalizedString(
            @"PROFILE_VIEW_PROFILE_AVATAR_FIELD", @"Label for the profile avatar field of the profile view.");
        fieldLabel.textColor = [UIColor blackColor];
        fieldLabel.font = [UIFont ows_mediumFontWithSize:fontSizePoints];
        [cell.contentView addSubview:fieldLabel];
        [fieldLabel autoPinLeadingToSuperView];
        [fieldLabel autoVCenterInSuperview];

        AvatarImageView *avatarView = weakSelf.avatarView;
        UIImageView *cameraImageView = weakSelf.cameraImageView;
        [cell.contentView addSubview:avatarView];
        [cell.contentView addSubview:cameraImageView];
        [weakSelf updateAvatarView];
        [avatarView autoPinTrailingToSuperView];
        [avatarView autoPinLeadingToTrailingOfView:fieldLabel margin:10.f];

        [avatarView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:kAvatarVMargin];
        [avatarView autoSetDimension:ALDimensionWidth toSize:kAvatarSizePoints];
        [avatarView autoSetDimension:ALDimensionHeight toSize:kAvatarSizePoints];
        [cameraImageView autoPinTrailingToView:avatarView];
        [cameraImageView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:avatarView];

        return cell;
    }
                         customRowHeight:avatarCellHeight
                         actionBlock:^{
                             [weakSelf avatarTapped];
                         }]];
    UIFont *footnoteFont = [UIFont ows_footnoteFont];
    [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.preservesSuperviewLayoutMargins = YES;
        cell.contentView.preservesSuperviewLayoutMargins = YES;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UILabel *label = [UILabel new];
        label.textColor = [UIColor ows_darkGrayColor];
        label.font = footnoteFont;
        label.textAlignment = NSTextAlignmentCenter;
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
        label.attributedText = text;
        label.numberOfLines = 0;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        [cell.contentView addSubview:label];
        [label autoPinLeadingToSuperView];
        [label autoPinTrailingToSuperView];
        [label autoVCenterInSuperview];

        return cell;
    }
                         customRowHeight:footnoteFont.lineHeight * 5
                         actionBlock:^{
                             [weakSelf openProfileInfoURL];
                         }]];
    [contents addSection:section];

    self.contents = contents;
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
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
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
            break;
        case ProfileViewMode_UpgradeOrNag:
            self.navigationItem.leftBarButtonItem =
                [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                              target:self
                                                              action:@selector(backOrSkipButtonPressed)];
            break;
        case ProfileViewMode_Registration:
            self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
                initWithTitle:NSLocalizedString(@"NAVIGATION_ITEM_SKIP_BUTTON", @"A button to skip a view.")
                        style:UIBarButtonItemStylePlain
                       target:self
                       action:@selector(backOrSkipButtonPressed)];
            break;
    }
    if (self.hasUnsavedChanges) {
        // If we have a unsaved changes, right item should be a "save" button.
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                          target:self
                                                          action:@selector(updatePressed)];
    }
}

- (void)updatePressed
{
    [self updateProfile];
}

- (void)updateProfile
{
    __weak ProfileViewController *weakSelf = self;

    // Show an activity indicator to block the UI during the profile upload.
    UIAlertController *alertController = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"PROFILE_VIEW_SAVING",
                                     @"Alert title that indicates the user's profile view is being saved.")
                         message:nil
                  preferredStyle:UIAlertControllerStyleAlert];

    [self presentViewController:alertController
                       animated:YES
                     completion:^{
                         [OWSProfileManager.sharedManager updateLocalProfileName:[self normalizedProfileName]
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

- (void)openProfileInfoURL
{
    [UIApplication.sharedApplication
        openURL:[NSURL URLWithString:@"https://support.whispersystems.org/hc/en-us/articles/115001110511"]];
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
