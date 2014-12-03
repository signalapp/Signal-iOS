//
//  SignalTabBarController.m
//  Signal
//
//  Created by Dylan Bourgeois on 05/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabaseViewMappings.h>
#import <YapDatabase/YapDatabaseViewTransaction.h>

#import "SignalTabBarController.h"

#import "TSAccountManager.h"
#import "TSDatabaseView.h"
#import "TSStorageManager.h"

@interface SignalTabBarController ()
@property YapDatabaseConnection *dbConnection;
@end

@implementation SignalTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.dbConnection = [TSStorageManager sharedManager].newDatabaseConnection;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:nil];
}

- (void)viewDidAppear:(BOOL)animated{
    if (![TSAccountManager isRegistered]){
        [self performSegueWithIdentifier:@"showSignupFlow" sender:self];
    }
}

- (void)yapDatabaseModified:(NSNotification *)notification {
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        numberOfItems = [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInAllGroups];
    }];
    
    NSNumber *badgeNumber = [NSNumber numberWithUnsignedInteger:numberOfItems];
    NSString *badgeValue  = nil;
    
    if (![badgeNumber isEqualToNumber:@0]) {
        badgeValue = [badgeNumber stringValue];
    }
    [[self signalsItem] setBadgeValue:badgeValue];
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:badgeNumber.integerValue];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (UITabBarItem*)signalsItem{
    return self.tabBar.items[1];
}

@end
