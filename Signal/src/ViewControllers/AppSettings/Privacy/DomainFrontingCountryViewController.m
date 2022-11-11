//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DomainFrontingCountryViewController.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/OWSCountryMetadata.h>
#import <SignalUI/OWSTableViewController.h>
#import <SignalUI/Theme.h>
#import <SignalUI/UIFont+OWS.h>
#import <SignalUI/UIView+SignalUI.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@interface DomainFrontingCountryViewController ()

@property (nonatomic, readonly) OWSTableViewController2 *tableViewController;

@end

#pragma mark -

@implementation DomainFrontingCountryViewController

- (void)loadView
{
    [super loadView];

    self.title = NSLocalizedString(
        @"CENSORSHIP_CIRCUMVENTION_COUNTRY_VIEW_TITLE", @"Title for the 'censorship circumvention country' view.");

    self.view.backgroundColor = Theme.tableViewBackgroundColor;
    self.tableViewController.useThemeBackgroundColors = YES;

    [self createViews];
}

- (void)createViews
{
    _tableViewController = [OWSTableViewController2 new];
    [self.view addSubview:self.tableViewController.view];
    [self.tableViewController.view autoPinEdgeToSuperviewSafeArea:ALEdgeLeading];
    [self.tableViewController.view autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];
    [_tableViewController.view autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [_tableViewController.view autoPinToBottomLayoutGuideOfViewController:self withInset:0];

    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    NSString *currentCountryCode = self.signalService.manualCensorshipCircumventionCountryCode;

    __weak DomainFrontingCountryViewController *weakSelf = self;

    OWSTableSection *section = [OWSTableSection new];
    section.headerTitle = NSLocalizedString(
        @"DOMAIN_FRONTING_COUNTRY_VIEW_SECTION_HEADER", @"Section title for the 'domain fronting country' view.");
    for (OWSCountryMetadata *countryMetadata in [OWSCountryMetadata allCountryMetadatas]) {
        [section addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 UITableViewCell *cell = [OWSTableItem newCell];
                                 [OWSTableItem configureCell:cell];
                                 cell.textLabel.text = countryMetadata.localizedCountryName;

                                 if ([countryMetadata.countryCode isEqualToString:currentCountryCode]) {
                                     cell.accessoryType = UITableViewCellAccessoryCheckmark;
                                 }

                                 return cell;
                             }
                             actionBlock:^{ [weakSelf selectCountry:countryMetadata]; }]];
    }
    [contents addSection:section];

    self.tableViewController.contents = contents;
}

- (void)selectCountry:(OWSCountryMetadata *)countryMetadata
{
    OWSAssertDebug(countryMetadata);

    self.signalService.manualCensorshipCircumventionCountryCode = countryMetadata.countryCode;

    [self.navigationController popViewControllerAnimated:YES];
}

@end

NS_ASSUME_NONNULL_END
