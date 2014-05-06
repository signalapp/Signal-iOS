#import <UIKit/UIKit.h>

@class CountryCodeViewController;

@protocol CountryCodeViewControllerDelegate <NSObject>

- (void)countryCodeViewController:(CountryCodeViewController *)vc
             didSelectCountryCode:(NSString *)code
                       forCountry:(NSString *)country;

- (void)countryCodeViewControllerDidCancel:(CountryCodeViewController *)vc;

@end

@interface CountryCodeViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>

@property (nonatomic, strong) IBOutlet UITableView *countryCodeTableView;
@property (nonatomic, strong) IBOutlet UISearchBar *searchBar;
@property (nonatomic, assign) id<CountryCodeViewControllerDelegate> delegate;

- (IBAction)cancelTapped:(id)sender;

@end
