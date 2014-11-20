#import "FavouriteTableViewCell.h"

#define FAVOURITE_TABLE_CELL_BORDER_WIDTH 1.0f

@implementation FavouriteTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
    self = [[NSBundle.mainBundle loadNibNamed:NSStringFromClass([self class]) owner:self options:nil] firstObject];
    
    if (self) {
        self.contactPictureView.layer.borderColor = [UIColor.lightGrayColor CGColor];
        self.contactPictureView.layer.masksToBounds = YES;
    }
    
    return self;
}

- (NSString*)reuseIdentifier {
    return NSStringFromClass([self class]);
}

- (void)configureWithContact:(Contact*)contact {
	
    self.nameLabel.attributedText = [self attributedStringForContact:contact];

    UIImage* image = contact.image;
    BOOL imageNotNil = image != nil;
    [self configureBorder:imageNotNil];

    if (imageNotNil) {
        self.contactPictureView.image = image;
    } else {
        self.contactPictureView.image = nil;
    }
}

- (void)callTapped {
    id delegate = self.delegate;
    [delegate favouriteTableViewCellTappedCall:self];
}

- (void)configureBorder:(BOOL)show {
    self.contactPictureView.layer.borderWidth = show ? FAVOURITE_TABLE_CELL_BORDER_WIDTH : 0;
    self.contactPictureView.layer.cornerRadius = show ? CGRectGetWidth(self.contactPictureView.frame)/2 : 0;
}

- (NSAttributedString*)attributedStringForContact:(Contact*)contact {
    NSMutableAttributedString* fullNameAttributedString = [[NSMutableAttributedString alloc] initWithString:contact.fullName];

    [fullNameAttributedString addAttribute:NSFontAttributeName
                                     value:[UIFont systemFontOfSize:self.nameLabel.font.pointSize]
                                     range:NSMakeRange(0, contact.firstName.length)];
    [fullNameAttributedString addAttribute:NSFontAttributeName
                                     value:[UIFont boldSystemFontOfSize:self.nameLabel.font.pointSize]
                                     range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    [fullNameAttributedString addAttribute:NSForegroundColorAttributeName
                                     value:UIColor.blackColor
                                     range:NSMakeRange(0, contact.fullName.length)];
    return fullNameAttributedString;
}

@end
