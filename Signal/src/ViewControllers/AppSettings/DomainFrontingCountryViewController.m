//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DomainFrontingCountryViewController.h"
#import "OWSCountryMetadata.h"
#import "OWSTableViewController.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalServiceKit/OWSSignalService.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@interface DomainFrontingCountryViewController ()

@property (nonatomic, readonly) OWSTableViewController *tableViewController;

@end

#pragma mark -

@implementation DomainFrontingCountryViewController

- (void)loadView
{
    [super loadView];

    self.title = NSLocalizedString(
        @"CENSORSHIP_CIRCUMVENTION_COUNTRY_VIEW_TITLE", @"Title for the 'censorship circumvention country' view.");

    self.view.backgroundColor = [UIColor whiteColor];

    [self createViews];
}

- (void)createViews
{
    _tableViewController = [OWSTableViewController new];
    [self.view addSubview:self.tableViewController.view];
    [_tableViewController.view autoPinWidthToSuperview];
    [_tableViewController.view autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [_tableViewController.view autoPinToBottomLayoutGuideOfViewController:self withInset:0];

    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    NSString *currentCountryCode = OWSSignalService.sharedInstance.manualCensorshipCircumventionCountryCode;

    __weak DomainFrontingCountryViewController *weakSelf = self;

    OWSTableSection *section = [OWSTableSection new];
    section.headerTitle = NSLocalizedString(
        @"DOMAIN_FRONTING_COUNTRY_VIEW_SECTION_HEADER", @"Section title for the 'domain fronting country' view.");
    for (OWSCountryMetadata *countryMetadata in [OWSCountryMetadata allCountryMetadatas]) {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            UITableViewCell *cell = [UITableViewCell new];
            cell.textLabel.text = countryMetadata.localizedCountryName;
            cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
            cell.textLabel.textColor = [UIColor blackColor];

            if ([countryMetadata.countryCode isEqualToString:currentCountryCode]) {
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
            }

            return cell;
        }
                             actionBlock:^{
                                 [weakSelf selectCountry:countryMetadata];
                             }]];
    }
    [contents addSection:section];

    self.tableViewController.contents = contents;
}

- (void)selectCountry:(OWSCountryMetadata *)countryMetadata
{
    OWSAssert(countryMetadata);

    OWSSignalService.sharedInstance.manualCensorshipCircumventionCountryCode = countryMetadata.countryCode;

    [self.navigationController popViewControllerAnimated:YES];
}

@end

NS_ASSUME_NONNULL_END
