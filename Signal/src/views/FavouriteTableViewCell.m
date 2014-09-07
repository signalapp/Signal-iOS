#import "FavouriteTableViewCell.h"

#define FAVOURITE_TABLE_CELL_BORDER_WIDTH 1.0f

@implementation FavouriteTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class]) owner:self options:nil][0];
    _contactPictureView.layer.borderColor = [[UIColor lightGrayColor] CGColor];
    _contactPictureView.layer.masksToBounds = YES;
    return self;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass([self class]);
}

- (void)configureWithContact:(Contact *)contact {
	
    _nameLabel.attributedText = [self attributedStringForContact:contact];

    UIImage *image = contact.image;
    BOOL imageNotNil = image != nil;
    [self configureBorder:imageNotNil];

    if (imageNotNil) {
        _contactPictureView.image = image;
    } else {
        _contactPictureView.image = nil;
    }
}

- (void)callTapped {
    [_delegate favouriteTableViewCellTappedCall:self];
}

- (void)configureBorder:(BOOL)show {
    _contactPictureView.layer.borderWidth = show ? FAVOURITE_TABLE_CELL_BORDER_WIDTH : 0;
    _contactPictureView.layer.cornerRadius = show ? CGRectGetWidth(_contactPictureView.frame)/2 : 0;
}

- (NSAttributedString *)attributedStringForContact:(Contact *)contact {
    NSMutableAttributedString *fullNameAttributedString = [[NSMutableAttributedString alloc] initWithString:contact.fullName];

    [fullNameAttributedString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:_nameLabel.font.pointSize] range:NSMakeRange(0, contact.firstName.length)];
    [fullNameAttributedString addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:_nameLabel.font.pointSize] range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    [fullNameAttributedString addAttribute:NSForegroundColorAttributeName value:[UIColor blackColor] range:NSMakeRange(0, contact.fullName.length)];
    return fullNameAttributedString;
}

@end
