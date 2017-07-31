//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ProfileViewController.h"
#import "Signal-Swift.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@interface ProfileViewController () <UITextFieldDelegate>
//<
// OWSTableViewControllerDelegate
//// , UISearchBarDelegate
//>

//@property (nonatomic, readonly) UISearchBar *searchBar;
//
//@property (nonatomic) NSArray<NSString *> *countryCodes;

@property (nonatomic) UITextField *nameTextField;

@property (nonatomic) AvatarImageView *avatarView;

@property (nonatomic) UILabel *avatarLabel;

@end

#pragma mark -

@implementation ProfileViewController

- (void)loadView
{
    [super loadView];

    self.view.backgroundColor = [UIColor whiteColor];
    [self.navigationController.navigationBar setTranslucent:NO];
    self.title = NSLocalizedString(@"PROFILE_VIEW_TITLE", @"Title for the profile view.");

    //    self.countryCodes = [PhoneNumberUtil countryCodesForSearchTerm:nil];

    //    self.navigationItem.leftBarButtonItem =
    //        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
    //                                                      target:self
    //                                                      action:@selector(dismissWasPressed:)];

    [self createViews];
}

- (void)createViews
{
    _nameTextField = [UITextField new];
    _nameTextField.font = [UIFont ows_mediumFontWithSize:18.f];
    //        _nameTextField.textAlignment = _nameTextField.textAlignmentUnnatural;
    _nameTextField.textColor = [UIColor ows_materialBlueColor];
    // TODO: Copy.
    _nameTextField.placeholder = NSLocalizedString(
        @"PROFILE_VIEW_NAME_DEFAULT_TEXT", @"Default text for the profile name field of the profile view.");
    _nameTextField.delegate = self;
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

    // Avatar
    OWSTableSection *avatarSection = [OWSTableSection new];
    avatarSection.headerTitle = NSLocalizedString(
        @"PROFILE_VIEW_AVATAR_SECTION_HEADER", @"Header title for the profile avatar field of the profile view.");
    const CGFloat kAvatarHeightPoints = 100.f;
    const CGFloat kAvatarTopMargin = 10.f;
    const CGFloat kAvatarBottomMargin = 10.f;
    const CGFloat kAvatarVSpacing = 10.f;
    CGFloat avatarCellHeight = round(
        kAvatarHeightPoints + kAvatarTopMargin + kAvatarBottomMargin + kAvatarVSpacing + self.avatarLabel.height);
    //    const CGFloat kCountryRowHeight = 50;
    //    const CGFloat kPhoneNumberRowHeight = 50;
    //    const CGFloat examplePhoneNumberRowHeight = self.examplePhoneNumberFont.lineHeight + 3.f;
    //    const CGFloat kButtonRowHeight = 60;
    [avatarSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
        //        SelectRecipientViewController *strongSelf = weakSelf;
        //        OWSCAssert(strongSelf);

        UITableViewCell *cell = [UITableViewCell new];
        cell.preservesSuperviewLayoutMargins = YES;
        cell.contentView.preservesSuperviewLayoutMargins = YES;

        // TODO: Use the current avatar.
        UIImage *defaultAvatarImage = [UIImage imageNamed:@"profile_avatar_default"];
        OWSAssert(defaultAvatarImage.size.width == kAvatarHeightPoints);
        OWSAssert(defaultAvatarImage.size.height == kAvatarHeightPoints);
        AvatarImageView *avatarView = weakSelf.avatarView;
        avatarView.image = defaultAvatarImage;

        [cell.contentView addSubview:avatarView];
        [avatarView autoHCenterInSuperview];
        [avatarView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:kAvatarTopMargin];

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

    // Profile
    OWSTableSection *nameSection = [OWSTableSection new];
    nameSection.headerTitle = NSLocalizedString(
        @"PROFILE_VIEW_NAME_SECTION_HEADER", @"Label for the profile name field of the profile view.");
    //    const CGFloat kCountryRowHeight = 50;
    //    const CGFloat kPhoneNumberRowHeight = 50;
    //    const CGFloat examplePhoneNumberRowHeight = self.examplePhoneNumberFont.lineHeight + 3.f;
    //    const CGFloat kButtonRowHeight = 60;
    [nameSection
        addItem:
            [OWSTableItem
                itemWithCustomCellBlock:^{
                    //        SelectRecipientViewController *strongSelf = weakSelf;
                    //        OWSCAssert(strongSelf);

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
                            //                                                      customRowHeight:kCountryRowHeight +
                            //                                                      kPhoneNumberRowHeight
                            //                                 + examplePhoneNumberRowHeight
                            //                                 + kButtonRowHeight
                            actionBlock:nil]];
    [contents addSection:nameSection];

    self.contents = contents;
}

//- (void)countryCodeWasSelected:(NSString *)countryCode
//{
//    OWSAssert(countryCode.length > 0);
//
//    NSString *callingCodeSelected = [PhoneNumberUtil callingCodeFromCountryCode:countryCode];
//    NSString *countryNameSelected = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
//    NSString *countryCodeSelected = countryCode;
//    [self.countryCodeDelegate ProfileViewController:self
//                                   didSelectCountryCode:countryCodeSelected
//                                            countryName:countryNameSelected
//                                            callingCode:callingCodeSelected];
//    [self.searchBar resignFirstResponder];
//    [self dismissViewControllerAnimated:YES completion:nil];
//}
//
//- (void)dismissWasPressed:(id)sender {
//    [self dismissViewControllerAnimated:YES completion:nil];
//}

- (void)avatarTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
    }
}

#pragma mark - UITextFieldDelegate

// TODO: This logic resides in both RegistrationViewController and here.
//       We should refactor it out into a utility function.
- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText
{
    return YES;

    //    [ViewControllerUtils phoneNumberTextField:textField
    //                shouldChangeCharactersInRange:range
    //                            replacementString:insertionText
    //                                  countryCode:_callingCode];
    //
    //    [self updatePhoneNumberButtonEnabling];
    //
    //    return NO; // inform our caller that we took care of performing the change
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    return YES;

    //    [textField resignFirstResponder];
    //    if ([self hasValidPhoneNumber]) {
    //        [self tryToSelectPhoneNumber];
    //    }
    //    return NO;
}

- (void)textFieldDidChange:(id)sender
{
    //    [self updatePhoneNumberButtonEnabling];
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
