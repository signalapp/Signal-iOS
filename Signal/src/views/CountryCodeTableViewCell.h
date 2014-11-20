#import <UIKit/UIKit.h>

@interface CountryCodeTableViewCell : UITableViewCell

@property (strong, nonatomic) IBOutlet UILabel* countryCodeLabel;
@property (strong, nonatomic) IBOutlet UILabel* countryNameLabel;

- (void)configureWithCountryCode:(NSString*)code andCountryName:(NSString*)name;

@end
