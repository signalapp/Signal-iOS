//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "UIView+OWS.h"
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

    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    BOOL isRTL = [backButton isRTL];

    // Nudge closer to the left edge to match default back button item.
    const CGFloat kExtraLeftPadding = isRTL ? +0 : -8;

    // Give some extra hit area to the back button. This is a little smaller
    // than the default back button, but makes sense for our left aligned title
    // view in the MessagesViewController
    const CGFloat kExtraRightPadding = isRTL ? -0 : +10;

    // Extra hit area above/below
    const CGFloat kExtraHeightPadding = 4;

    // Matching the default backbutton placement is tricky.
    // We can't just adjust the imageEdgeInsets on a UIBarButtonItem directly,
    // so we adjust the imageEdgeInsets on a UIButton, then wrap that
    // in a UIBarButtonItem.
    [backButton addTarget:target action:selector forControlEvents:UIControlEventTouchUpInside];

    UIImage *backImage = [UIImage imageNamed:(isRTL ? @"NavBarBackRTL" : @"NavBarBack")];
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
