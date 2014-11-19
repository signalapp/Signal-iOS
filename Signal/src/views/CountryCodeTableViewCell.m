#import "CountryCodeTableViewCell.h"

@implementation CountryCodeTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier {
    self = [[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class])
                                          owner:self
                                        options:nil] firstObject];
    return self;
}

- (NSString*)reuseIdentifier {
    return NSStringFromClass([self class]);
}

- (void)configureWithCountryCode:(NSString*)code andCountryName:(NSString*)name {
    self.countryCodeLabel.text = code;
    self.countryNameLabel.text = name;
}

@end
