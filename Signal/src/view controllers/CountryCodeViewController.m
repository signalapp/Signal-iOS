
#import "CountryCodeViewController.h"
#import "CountryCodeTableViewCell.h"
#import "NBPhoneNumberUtil.h"
#import "PhoneNumber.h"
#import "PhoneNumberUtil.h"

static NSString* const CONTRY_CODE_TABLE_CELL_IDENTIFIER = @"CountryCodeTableViewCell";

@interface CountryCodeViewController ()

@property (strong, nonatomic) NSArray* countryCodes;

@end

@implementation CountryCodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.countryCodes = [PhoneNumberUtil countryCodesForSearchTerm:nil];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Actions

- (IBAction)cancelTapped:(id)sender {
    id delegate = self.delegate;
    [delegate countryCodeViewControllerDidCancel:self];
}


#pragma mark - UITableViewDelegate

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.countryCodes.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    CountryCodeTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:CONTRY_CODE_TABLE_CELL_IDENTIFIER];
    
    if (!cell) {
        cell = [[CountryCodeTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                               reuseIdentifier:CONTRY_CODE_TABLE_CELL_IDENTIFIER];
    }
    
    NSString* countryCode = self.countryCodes[(NSUInteger)indexPath.row];
    NSString* callingCode = [PhoneNumberUtil callingCodeFromCountryCode:countryCode];
    NSString* countryName = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
    [cell configureWithCountryCode:callingCode andCountryName:countryName];
    
    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    
    NSString* countryCode = self.countryCodes[(NSUInteger)indexPath.row];
    NSString* callingCode = [PhoneNumberUtil callingCodeFromCountryCode:countryCode];
    NSString* countryName = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
    
    id delegate = self.delegate;
    [delegate countryCodeViewController:self
                   didSelectCountryCode:callingCode
                             forCountry:countryName];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar*)searchBar textDidChange:(NSString*)searchText {
    self.countryCodes = [PhoneNumberUtil countryCodesForSearchTerm:searchText];
    [self.countryCodeTableView reloadData];
}

@end
