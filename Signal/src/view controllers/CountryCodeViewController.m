//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "CountryCodeTableViewCell.h"
#import "CountryCodeViewController.h"
#import "PhoneNumberUtil.h"
#import "FunctionalUtil.h"

static NSString *const CONTRY_CODE_TABLE_CELL_IDENTIFIER    = @"CountryCodeTableViewCell";
static NSString *const kUnwindToCountryCodeWasSelectedSegue = @"UnwindToCountryCodeWasSelectedSegue";


@interface CountryCodeViewController () {
    NSArray *_countryCodes;
}

@end

@implementation CountryCodeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
    _countryCodes = [PhoneNumberUtil countryCodesForSearchTerm:nil];
    self.title    = NSLocalizedString(@"COUNTRYCODE_SELECT_TITLE", @"");
    self.searchBar.delegate = self;
}

#pragma mark - UITableViewDelegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_countryCodes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CountryCodeTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CONTRY_CODE_TABLE_CELL_IDENTIFIER];
    if (!cell) {
        cell = [[CountryCodeTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                               reuseIdentifier:CONTRY_CODE_TABLE_CELL_IDENTIFIER];
    }

    NSString *countryCode = _countryCodes[(NSUInteger)indexPath.row];
    OWSAssert(countryCode.length > 0);
    OWSAssert([PhoneNumberUtil countryNameFromCountryCode:countryCode].length > 0);
    OWSAssert([PhoneNumberUtil callingCodeFromCountryCode:countryCode].length > 0);
    OWSAssert(![[PhoneNumberUtil callingCodeFromCountryCode:countryCode] isEqualToString:@"+0"]);

    [cell configureWithCountryCode:[PhoneNumberUtil callingCodeFromCountryCode:countryCode]
                    andCountryName:[PhoneNumberUtil countryNameFromCountryCode:countryCode]];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *countryCode = _countryCodes[(NSUInteger)indexPath.row];
    _callingCodeSelected  = [PhoneNumberUtil callingCodeFromCountryCode:countryCode];
    _countryNameSelected  = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
    [self.searchBar resignFirstResponder];
    [self performSegueWithIdentifier:kUnwindToCountryCodeWasSelectedSegue sender:self];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44.0f;
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    _countryCodes = [PhoneNumberUtil countryCodesForSearchTerm:searchText];
    [self.countryCodeTableView reloadData];
}

- (void)filterContentForSearchText:(NSString *)searchText scope:(NSString *)scope {
    _countryCodes = [PhoneNumberUtil countryCodesForSearchTerm:searchText];
}

@end
