//
//  TSRecipient.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 17/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager+IdentityKeyStore.h"
#import "TSRecipient.h"

@implementation TSRecipient

+ (NSString*)collection{
    return @"TSRecipient";
}

- (instancetype)initWithTextSecureIdentifier:(NSString*)textSecureIdentifier relay:(NSString *)relay{
    self = [super initWithUniqueId:textSecureIdentifier];
    
    if (self) {
        _devices     = [NSMutableOrderedSet orderedSetWithObject:[NSNumber numberWithInt:1]];
        _relay       = relay;
    }
    
    return self;
}

+ (instancetype)recipientWithTextSecureIdentifier:(NSString*)textSecureIdentifier withTransaction:(YapDatabaseReadTransaction*)transaction{
    return [self fetchObjectWithUniqueID:textSecureIdentifier transaction:transaction];
}

- (NSMutableOrderedSet*)devices{
    return [_devices copy];
}

- (void)addDevices:(NSSet *)set{
    [self checkDevices];
    [_devices unionSet:set];
}

- (void)removeDevices:(NSSet *)set{
    [self checkDevices];
    [_devices minusSet:set];
}

- (void)checkDevices {
    if (_devices == nil || ![_devices isKindOfClass:[NSMutableOrderedSet class]]) {
        _devices = [NSMutableOrderedSet orderedSetWithObject:[NSNumber numberWithInt:1]];
    }
}

@end
