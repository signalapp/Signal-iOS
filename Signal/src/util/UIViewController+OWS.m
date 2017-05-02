//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "UIViewController+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation UIViewController (OWS)

- (UIBarButtonItem *)createOWSBackButton
{
    return [self createOWSBackButtonWithTarget:self selector:@selector(backButtonPressed:)];
}

- (UIBarButtonItem *)createOWSBackButtonWithTarget:(id)target selector:(SEL)selector
{
    OWSAssert(target);
    OWSAssert(selector);

    // Nudge closer to the left edge to match default back button item.
    const CGFloat kExtraLeftPadding = -8;

    // Give some extra hit area to the back button. This is a little smaller
    // than the default back button, but makes sense for our left aligned title
    // view in the MessagesViewController
    const CGFloat kExtraRightPadding = 10;

    // Extra hit area above/below
    const CGFloat kExtraHeightPadding = 4;

    // Matching the default backbutton placement is tricky.
    // We can't just adjust the imageEdgeInsets on a UIBarButtonItem directly,
    // so we adjust the imageEdgeInsets on a UIButton, then wrap that
    // in a UIBarButtonItem.
    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [backButton addTarget:target action:selector forControlEvents:UIControlEventTouchUpInside];

    UIImage *backImage = [UIImage imageNamed:@"NavBarBack"];
    OWSAssert(backImage);
    [backButton setImage:backImage forState:UIControlStateNormal];

    backButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;

    // Default back button is 1.5 pixel lower than our extracted image.
    const CGFloat kTopInsetPadding = 1.5;
    backButton.imageEdgeInsets = UIEdgeInsetsMake(kTopInsetPadding, kExtraLeftPadding, 0, 0);

    backButton.frame = CGRectMake(0, 0, backImage.size.width + kExtraRightPadding, backImage.size.height + kExtraHeightPadding);

    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithCustomView:backButton];

    return backItem;
}

#pragma mark - Event Handling

- (void)backButtonPressed:(id)sender {
    [self.navigationController popViewControllerAnimated:YES];
}

@end

NS_ASSUME_NONNULL_END
