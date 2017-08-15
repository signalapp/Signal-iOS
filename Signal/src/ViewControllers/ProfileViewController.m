//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ProfileViewController.h"
#import "AppDelegate.h"
#import "AvatarViewHelper.h"
#import "OWSProfileManager.h"
#import "Signal-Swift.h"
#import "SignalsNavigationController.h"
#import "SignalsViewController.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "UIViewController+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@interface ProfileViewController () <UITextFieldDelegate, AvatarViewHelperDelegate>

@property (nonatomic, readonly) AvatarViewHelper *avatarViewHelper;

@property (nonatomic) UITextField *nameTextField;

@property (nonatomic) AvatarImageView *avatarView;

@property (nonatomic) UIImageView *cameraImageView;

@property (nonatomic) UILabel *avatarLabel;

@property (nonatomic, nullable) UIImage *avatar;

@property (nonatomic) BOOL hasUnsavedChanges;

@end

#pragma mark -

@implementation ProfileViewController

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

    _avatarLabel = [UILabel new];
    _avatarLabel.font = [UIFont ows_regularFontWithSize:14.f];
    _avatarLabel.textColor = [UIColor ows_materialBlueColor];
    // TODO: Copy.
    _avatarLabel.text
        = NSLocalizedString(@"PROFILE_VIEW_AVATAR_INSTRUCTIONS", @"Instructions for how to change the profile avatar.");
    [_avatarLabel sizeToFit];

    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak ProfileViewController *weakSelf = self;

    // Profile Avatar
    OWSTableSection *avatarSection = [OWSTableSection new];
    avatarSection.headerTitle = NSLocalizedString(
        @"PROFILE_VIEW_AVATAR_SECTION_HEADER", @"Header title for the profile avatar field of the profile view.");
    const CGFloat kAvatarSizePoints = 100.f;
    const CGFloat kAvatarTopMargin = 10.f;
    const CGFloat kAvatarBottomMargin = 10.f;
    const CGFloat kAvatarVSpacing = 10.f;
    CGFloat avatarCellHeight
        = round(kAvatarSizePoints + kAvatarTopMargin + kAvatarBottomMargin + kAvatarVSpacing + self.avatarLabel.height);
    [avatarSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.preservesSuperviewLayoutMargins = YES;
        cell.contentView.preservesSuperviewLayoutMargins = YES;

        AvatarImageView *avatarView = weakSelf.avatarView;
        UIImageView *cameraImageView = weakSelf.cameraImageView;
        [cell.contentView addSubview:avatarView];
        [cell.contentView addSubview:cameraImageView];
        [weakSelf updateAvatarView];
        [avatarView autoHCenterInSuperview];
        [avatarView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:kAvatarTopMargin];
        [avatarView autoSetDimension:ALDimensionWidth toSize:kAvatarSizePoints];
        [avatarView autoSetDimension:ALDimensionHeight toSize:kAvatarSizePoints];
        [cameraImageView autoPinTrailingToView:avatarView];
        [cameraImageView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:avatarView];

        UILabel *avatarLabel = weakSelf.avatarLabel;
        [cell.contentView addSubview:avatarLabel];
        [avatarLabel autoHCenterInSuperview];
        [avatarLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:kAvatarBottomMargin];

        cell.userInteractionEnabled = YES;
        [cell
            addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTapped:)]];

        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
                                                 customRowHeight:avatarCellHeight
                                                     actionBlock:nil]];
    [contents addSection:avatarSection];

    // Profile Name
    OWSTableSection *nameSection = [OWSTableSection new];
    nameSection.headerTitle = NSLocalizedString(
        @"PROFILE_VIEW_NAME_SECTION_HEADER", @"Label for the profile name field of the profile view.");
    [nameSection
        addItem:
            [OWSTableItem
                itemWithCustomCellBlock:^{
                    UITableViewCell *cell = [UITableViewCell new];
                    cell.preservesSuperviewLayoutMargins = YES;
                    cell.contentView.preservesSuperviewLayoutMargins = YES;

                    UITextField *nameTextField = weakSelf.nameTextField;
                    [cell.contentView addSubview:nameTextField];
                    [nameTextField autoPinLeadingToSuperView];
                    [nameTextField autoPinTrailingToSuperView];
                    [nameTextField autoVCenterInSuperview];

                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    return cell;
                }
                            actionBlock:nil]];
    [contents addSection:nameSection];

    self.contents = contents;
}

#pragma mark - Event Handling

- (void)backButtonPressed:(id)sender
{
    [self leaveViewCheckingForUnsavedChanges:^{
        [self.navigationController popViewControllerAnimated:YES];
    }];
}

- (void)leaveViewCheckingForUnsavedChanges:(void (^_Nonnull)())leaveViewBlock
{
    OWSAssert(leaveViewBlock);

    [self.nameTextField resignFirstResponder];

    if (!self.hasUnsavedChanges) {
        // If user made no changes, return to conversation settings view.
        leaveViewBlock();
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
                                             leaveViewBlock();
                                         }]];
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)avatarTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self.avatarViewHelper showChangeAvatarUI];
    }
}

- (void)setHasUnsavedChanges:(BOOL)hasUnsavedChanges
{
    _hasUnsavedChanges = hasUnsavedChanges;

    [self updateNavigationItem];
}

- (void)updateNavigationItem
{
    // The navigation bar is hidden in the registration workflow.
    [self.navigationController setNavigationBarHidden:NO animated:YES];

    UIBarButtonItem *rightItem = nil;
    switch (self.profileViewMode) {
        case ProfileViewMode_AppSettings:
            self.navigationItem.leftBarButtonItem =
                [self createOWSBackButtonWithTarget:self selector:@selector(backButtonPressed:)];
            break;
        case ProfileViewMode_Registration:
        case ProfileViewMode_UpgradeOrNag:
            // Registration and "upgrade or nag" mode don't need a back button.
            self.navigationItem.hidesBackButton = YES;

            // Registration and "upgrade or nag" mode have "skip" or "update".
            //
            // TODO: Should this be some other verb instead of "update"?
            rightItem = [[UIBarButtonItem alloc]
                initWithTitle:NSLocalizedString(@"NAVIGATION_ITEM_SKIP_BUTTON", @"A button to skip a view.")
                        style:UIBarButtonItemStylePlain
                       target:self
                       action:@selector(skipPressed)];
            break;
    }
    if (self.hasUnsavedChanges) {
        rightItem = [[UIBarButtonItem alloc]
            initWithTitle:NSLocalizedString(@"EDIT_GROUP_UPDATE_BUTTON", @"The title for the 'update group' button.")
                    style:UIBarButtonItemStylePlain
                   target:self
                   action:@selector(updatePressed)];
    }
    self.navigationItem.rightBarButtonItem = rightItem;
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

- (void)skipPressed
{
    [self leaveViewCheckingForUnsavedChanges:^{
        [self profileCompletedOrSkipped];
    }];
}

- (void)profileCompletedOrSkipped
{
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
