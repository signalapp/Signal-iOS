//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugSettingsTableViewController.h"
#import "UIFont+OWS.h"
#import <SignalServiceKit/TSDatabaseView.h>
#import <SignalServiceKit/TSStorageManager.h>

@implementation DebugSettingsTableViewController

- (void)loadView
{
    self.tableViewStyle = UITableViewStylePlain;
    [super loadView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self.navigationController.navigationBar setTranslucent:NO];

    self.title = @"Debugging";

    [self updateTableContents];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self updateTableContents];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];
    OWSTableSection *section = [OWSTableSection new];

    __block NSUInteger threadCount;
    __block NSUInteger messageCount;
    [TSStorageManager.sharedManager.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        threadCount = [[transaction ext:TSThreadDatabaseViewExtensionName] numberOfItemsInAllGroups];
        messageCount = [[transaction ext:TSMessageDatabaseViewExtensionName] numberOfItemsInAllGroups];
    }];

    [section addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Threads: %zd", threadCount]]];
    [section addItem:[OWSTableItem labelItemWithText:[NSString stringWithFormat:@"Messages: %zd", messageCount]]];

    [contents addSection:section];

    self.contents = contents;
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
