//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ProfileViewController.h"
#import "AvatarViewHelper.h"
#import "OWSProfileManager.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import "UIViewController+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@interface ProfileViewController () <UITextFieldDelegate, AvatarViewHelperDelegate>

@property (nonatomic, readonly) AvatarViewHelper *avatarViewHelper;

@property (nonatomic) UITextField *nameTextField;

@property (nonatomic) AvatarImageView *avatarView;

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
    self.navigationItem.leftBarButtonItem =
        [self createOWSBackButtonWithTarget:self selector:@selector(backButtonPressed:)];

    _avatarViewHelper = [AvatarViewHelper new];
    _avatarViewHelper.delegate = self;

    _avatar = [OWSProfileManager.sharedManager localProfileAvatarImage];

    [self createViews];
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
        [weakSelf updateAvatarView];
        [cell.contentView addSubview:avatarView];
        [avatarView autoHCenterInSuperview];
        [avatarView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:kAvatarTopMargin];
        [avatarView autoSetDimension:ALDimensionWidth toSize:kAvatarSizePoints];
        [avatarView autoSetDimension:ALDimensionHeight toSize:kAvatarSizePoints];

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
    [self.nameTextField resignFirstResponder];

    if (!self.hasUnsavedChanges) {
        // If user made no changes, return to conversation settings view.
        [self.navigationController popViewControllerAnimated:YES];
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
                                             [self.navigationController popViewControllerAnimated:YES];
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

    if (hasUnsavedChanges) {
        self.navigationItem.rightBarButtonItem = (self.hasUnsavedChanges
                ? [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"EDIT_GROUP_UPDATE_BUTTON",
                                                             @"The title for the 'update group' button.")
                                                   style:UIBarButtonItemStylePlain
                                                  target:self
                                                  action:@selector(updatePressed)]
                : nil);
    }
}

- (void)updatePressed
{
    [self updateProfile];
}

- (void)updateProfile
{
    __weak ProfileViewController *weakSelf = self;
    [OWSProfileManager.sharedManager updateLocalProfileName:self.nameTextField.text
                                                avatarImage:self.avatar
                                                    success:^{
                                                        [weakSelf.navigationController popViewControllerAnimated:YES];
                                                    }
                                                    failure:^{
                                                        // TODO: Handle failure.
                                                    }];
}

#pragma mark - UITextFieldDelegate

// TODO: This logic resides in both RegistrationViewController and here.
//       We should refactor it out into a utility function.
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
    self.avatarView.image = (self.avatar ?: [UIImage imageNamed:@"profile_avatar_default"]);
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

    // TODO: Crop to square and possible resize.

    self.avatar = image;
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
