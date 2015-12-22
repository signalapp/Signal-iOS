#import <UIKit/UIKit.h>

@class CountryCodeViewController;

@protocol CountryCodeViewControllerDelegate <NSObject>

- (void)countryCodeViewController:(CountryCodeViewController *)vc
             didSelectCountryCode:(NSString *)code
                       forCountry:(NSString *)country;

- (void)countryCodeViewControllerDidCancel:(CountryCodeViewController *)vc;

@end

@interface CountryCodeViewController
    : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UISearchDisplayDelegate>

@property (nonatomic, strong) IBOutlet UITableView *countryCodeTableView;
@property (nonatomic, strong) IBOutlet UISearchBar *searchBar;
@property (nonatomic, assign) id<CountryCodeViewControllerDelegate> delegate;
@property (nonatomic, strong) NSString *callingCodeSelected;
@property (nonatomic, strong) NSString *countryNameSelected;

@end
