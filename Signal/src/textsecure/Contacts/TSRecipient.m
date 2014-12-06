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
@property (nonatomic, copy)   NSData *verifiedKey;

@end

@implementation TSRecipient

+ (NSString*)collection{
    return @"TSRecipient";
}

- (instancetype)initWithTextSecureIdentifier:(NSString*)textSecureIdentifier relay:(NSString *)relay{
    self = [super initWithUniqueId:textSecureIdentifier];
    
    if (self) {
        _devices     = [NSMutableSet setWithObject:[NSNumber numberWithInt:1]];
        _verifiedKey = nil;
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

#pragma mark Fingerprint verification

- (BOOL)hasVerifiedFingerprint{
    if (self.verifiedKey) {
        BOOL equalsStoredValue = [self.verifiedKey isEqualToData:[[TSStorageManager sharedManager] identityKeyForRecipientId:self.uniqueId]];
        
        if (equalsStoredValue) {
            return YES;
        } else{
            self.verifiedKey = nil;
            return NO;
        }
        
    } else{
        return NO;
    }
}

- (void)setFingerPrintVerified:(BOOL)verified transaction:(YapDatabaseReadTransaction*)transaction{
    if (verified) {
        self.verifiedKey = [[TSStorageManager sharedManager] identityKeyForRecipientId:self.uniqueId];
    } else{
        self.verifiedKey = nil;
    }
}


@end
