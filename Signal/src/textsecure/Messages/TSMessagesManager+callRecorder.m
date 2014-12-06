//
//  TSMessagesManager+callRecorder.m
//  Signal
//
//  Created by Frederic Jacobs on 26/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessagesManager+callRecorder.h"
#import <YapDatabase/YapDatabaseConnection.h>

#import "Environment.h"
#import "ContactsManager.h"

@implementation TSMessagesManager (callRecorder)

- (void)storePhoneCall:(TSCall*)call{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [call saveWithTransaction:transaction];
    }];
}


@end
