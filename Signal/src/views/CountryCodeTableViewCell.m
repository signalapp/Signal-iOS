#import "CountryCodeTableViewCell.h"

@implementation CountryCodeTableViewCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    return self;
}

- (NSString *)reuseIdentifier {
    return NSStringFromClass(self.class);
}

- (void)configureWithCountryCode:(NSString *)code andCountryName:(NSString *)name {
    _countryCodeLabel.text = code;
    _countryNameLabel.text = name;
}

@end
