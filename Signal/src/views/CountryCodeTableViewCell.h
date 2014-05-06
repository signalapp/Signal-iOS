#import <UIKit/UIKit.h>

@interface CountryCodeTableViewCell : UITableViewCell

@property (nonatomic, strong) IBOutlet UILabel *countryCodeLabel;
@property (nonatomic, strong) IBOutlet UILabel *countryNameLabel;

- (void)configureWithCountryCode:(NSString *)code andCountryName:(NSString *)name;

@end
