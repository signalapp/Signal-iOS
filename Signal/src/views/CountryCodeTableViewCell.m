#import "CountryCodeTableViewCell.h"

@implementation CountryCodeTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [[[NSBundle mainBundle] loadNibNamed:NSStringFromClass([self class])
                                          owner:self
                                        options:nil] firstObject];
    return self;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass([self class]);
}

- (void)configureWithCountryCode:(NSString *)code andCountryName:(NSString *)name {
    _countryCodeLabel.text = code;
    _countryNameLabel.text = name;
}

@end
