#import "ContactTableViewCell.h"

#define CONTACT_TABLE_CELL_BORDER_WIDTH 1.0f

@implementation ContactTableViewCell

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

- (void)configureBorder:(BOOL)show {
    _contactPictureView.layer.borderWidth = show ? CONTACT_TABLE_CELL_BORDER_WIDTH : 0;
    _contactPictureView.layer.cornerRadius = show ? CGRectGetWidth(_contactPictureView.frame)/2 : 0;
}

- (NSAttributedString *)attributedStringForContact:(Contact *)contact {
    NSMutableAttributedString *fullNameAttributedString = [[NSMutableAttributedString alloc] initWithString:contact.fullName];

    UIFont *firstNameFont;
    UIFont *lastNameFont;
    
    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        firstNameFont = [UIFont boldSystemFontOfSize:_nameLabel.font.pointSize];
        lastNameFont  = [UIFont systemFontOfSize:_nameLabel.font.pointSize];
    } else{
        firstNameFont = [UIFont systemFontOfSize:_nameLabel.font.pointSize];
        lastNameFont  = [UIFont boldSystemFontOfSize:_nameLabel.font.pointSize];
    }
    [fullNameAttributedString addAttribute:NSFontAttributeName value:firstNameFont range:NSMakeRange(0, contact.firstName.length)];
    [fullNameAttributedString addAttribute:NSFontAttributeName value:lastNameFont range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    
    [fullNameAttributedString addAttribute:NSForegroundColorAttributeName value:[UIColor blackColor] range:NSMakeRange(0, contact.fullName.length)];
    return fullNameAttributedString;
}

@end
