#import "LeftSideMenuCell.h"
#import "UIUtil.h"

@implementation LeftSideMenuCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [[NSBundle.mainBundle loadNibNamed:NSStringFromClass(self.class)
                                          owner:self
                                        options:nil] firstObject];
    return self;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (highlighted) {
        _menuTitleLabel.textColor = [UIUtil darkBackgroundColor];
    } else {
        _menuTitleLabel.textColor = UIUtil.whiteColor;
    }
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass(self.class);
}

@end
