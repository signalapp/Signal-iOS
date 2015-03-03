//
//  TSRecipient.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 17/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager+IdentityKeyStore.h"
#import "TSRecipient.h"

@interface TSRecipient ()

@property (nonatomic, retain) NSMutableSet *devices;

@end

@implementation TSRecipient

+ (NSString*)collection{
    return @"TSRecipient";
}

- (instancetype)initWithTextSecureIdentifier:(NSString*)textSecureIdentifier relay:(NSString *)relay{
    self = [super initWithUniqueId:textSecureIdentifier];
    
    if (self) {
        _devices     = [NSMutableSet setWithObject:[NSNumber numberWithInt:1]];
        _relay       = relay;
    }
    
    return self;
}

+ (instancetype)recipientWithTextSecureIdentifier:(NSString*)textSecureIdentifier withTransaction:(YapDatabaseReadTransaction*)transaction{
    return [self fetchObjectWithUniqueID:textSecureIdentifier transaction:transaction];
}

- (NSSet*)devices{
    return [_devices copy];
}

- (void)addDevices:(NSSet *)set{
    [_devices unionSet:set];
}

- (void)removeDevices:(NSSet *)set{
    [_devices minusSet:set];
}

@end
