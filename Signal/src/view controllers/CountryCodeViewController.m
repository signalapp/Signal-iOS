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
    _countryCodes = [self countryCodesForSearchTerm:nil];
    self.title    = NSLocalizedString(@"COUNTRYCODE_SELECT_TITLE", @"");
    self.searchBar.delegate = self;
}

- (NSArray *)countryCodesForSearchTerm:(NSString *)searchTerm {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *countryCode in [PhoneNumberUtil countryCodesForSearchTerm:searchTerm]) {
        NSString *callingCode = [self callingCodeFromCountryCode:countryCode];
        if (callingCode != nil &&
            ![callingCode isEqualToString:@"+0"]) {
            [result addObject:countryCode];
        }
    }
    
    if (searchTerm.length > 0) {
        NSArray *allCountryCodes = [self countryCodesForSearchTerm:nil];
        // We want to ignore + when using a search term like "+44".
        // We also want to ignore punctuation, etc.
        // To keep things simple, we just remove everything except letters and numbers.
        NSCharacterSet *charactersToRemove = [[NSMutableCharacterSet alphanumericCharacterSet] invertedSet];
        NSString *simplifiedSearchTerm = [[searchTerm componentsSeparatedByCharactersInSet:charactersToRemove]
                                          componentsJoinedByString:@"" ];
        for (NSString *split in [simplifiedSearchTerm componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
            NSString *simplifiedSplit = split.lowercaseString;
            OWSAssert(simplifiedSplit.length > 0);
            for (NSString *countryCode in allCountryCodes) {
                if ([countryCode.lowercaseString rangeOfString:simplifiedSplit].location != NSNotFound) {
                    [result addObject:countryCode];
                    continue;
                }
                NSString *countryName = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
                OWSAssert(countryName.length > 0);
                if ([countryName.lowercaseString rangeOfString:simplifiedSplit].location != NSNotFound) {
                    [result addObject:countryCode];
                    continue;
                }
                NSString *callingCode = [self callingCodeFromCountryCode:countryCode];
                OWSAssert(callingCode.length > 0);
                if ([callingCode.lowercaseString rangeOfString:simplifiedSplit].location != NSNotFound) {
                    [result addObject:countryCode];
                    continue;
                }
            }
        }
        
        // De-duplicate and sort.
        //
        // The results of this method should be sorted by _country name_, not
        // country code, so we sort by filtering allCountryCodes, which is
        // already sorted in the correct order.
        NSSet *countryCodeSet = [NSSet setWithArray:result];
        return [allCountryCodes filter:^int(NSString *countryCode) {
            return [countryCodeSet containsObject:countryCode];
        }];
    }
    
    return result;
}

- (NSString *)callingCodeFromCountryCode:(NSString *)countryCode {
    NSString *callingCode = [PhoneNumberUtil callingCodeFromCountryCode:countryCode];
    if ([countryCode isEqualToString:@"AQ"]) {
        // Antarctica
        callingCode = @"+672";
    } else if ([countryCode isEqualToString:@"BV"]) {
        // Bouvet Island
        callingCode = @"+55";
    } else if ([countryCode isEqualToString:@"IC"]) {
        // Canary Islands
        callingCode = @"+34";
    } else if ([countryCode isEqualToString:@"EA"]) {
        // Ceuta & Melilla
        callingCode = @"+34";
    } else if ([countryCode isEqualToString:@"CP"]) {
        // Clipperton Island
        //
        // This country code should be filtered - it does not appear to have a calling code.
        return nil;
    } else if ([countryCode isEqualToString:@"DG"]) {
        // Diego Garcia
        callingCode = @"+246";
    } else if ([countryCode isEqualToString:@"TF"]) {
        // French Southern Territories
        callingCode = @"+262";
    } else if ([countryCode isEqualToString:@"HM"]) {
        // Heard & McDonald Islands
        callingCode = @"+672";
    } else if ([countryCode isEqualToString:@"XK"]) {
        // Kosovo
        callingCode = @"+383";
    } else if ([countryCode isEqualToString:@"PN"]) {
        // Pitcairn Islands
        callingCode = @"+64";
    } else if ([countryCode isEqualToString:@"GS"]) {
        // So. Georgia & So. Sandwich Isl.
        callingCode = @"+500";
    } else if ([countryCode isEqualToString:@"UM"]) {
        // U.S. Outlying Islands
        callingCode = @"+1";
    }
    
    return callingCode;
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
    OWSAssert([self callingCodeFromCountryCode:countryCode].length > 0);
    OWSAssert(![[self callingCodeFromCountryCode:countryCode] isEqualToString:@"+0"]);

    [cell configureWithCountryCode:[self callingCodeFromCountryCode:countryCode]
                    andCountryName:[PhoneNumberUtil countryNameFromCountryCode:countryCode]];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *countryCode = _countryCodes[(NSUInteger)indexPath.row];
    _callingCodeSelected  = [self callingCodeFromCountryCode:countryCode];
    _countryNameSelected  = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
    [self.searchBar resignFirstResponder];
    [self performSegueWithIdentifier:kUnwindToCountryCodeWasSelectedSegue sender:self];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44.0f;
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    _countryCodes = [self countryCodesForSearchTerm:searchText];
    [self.countryCodeTableView reloadData];
}

- (void)filterContentForSearchText:(NSString *)searchText scope:(NSString *)scope {
    _countryCodes = [self countryCodesForSearchTerm:searchText];
}

@end
