#import <UIKit/UIKit.h>

@class CountryCodeViewController;

@protocol CountryCodeViewControllerDelegate <NSObject>

- (void)countryCodeViewController:(CountryCodeViewController*)vc
             didSelectCountryCode:(NSString*)code
                       forCountry:(NSString*)country;

- (void)countryCodeViewControllerDidCancel:(CountryCodeViewController*)vc;

@end

@interface CountryCodeViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>

@property (strong, nonatomic) IBOutlet UITableView* countryCodeTableView;
@property (strong, nonatomic) IBOutlet UISearchBar* searchBar;
@property (nonatomic) id<CountryCodeViewControllerDelegate> delegate;

- (IBAction)cancelTapped:(id)sender;

@end
