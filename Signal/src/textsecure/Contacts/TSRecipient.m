//
//  TSRecipient.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 17/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager+IdentityKeyStore.h"
#import "TSRecipient.h"

@interface TSRecipient (){
    NSMutableSet *devices;
    NSData *verifiedKey;
}

@end

@implementation TSRecipient

+ (NSString*)collection{
    return @"TSRecipient";
}

- (instancetype)initWithTextSecureIdentifier:(NSString*)textSecureIdentifier{
    self = [super initWithUniqueId:textSecureIdentifier];
    
    if (self) {
        devices     = [NSMutableSet setWithObject:[NSNumber numberWithInt:1]];
        verifiedKey = nil;
    }
    
    return self;
}

+ (instancetype)recipientWithTextSecureIdentifier:(NSString*)textSecureIdentifier withTransaction:(YapDatabaseReadTransaction*)transaction{
    TSRecipient *recipient = [self fetchObjectWithUniqueID:textSecureIdentifier transaction:transaction];
    
    if (!recipient) {
        recipient = [[self alloc] initWithTextSecureIdentifier:textSecureIdentifier];
    }
    return recipient;
}

- (NSSet*)devices{
    return [devices copy];
}

- (void)addDevices:(NSSet *)set{
    [devices unionSet:set];
}

- (void)removeDevices:(NSSet *)set{
    [devices minusSet:set];
}

#pragma mark Fingerprint verification

- (BOOL)hasVerifiedFingerprint{
    if (verifiedKey) {
        BOOL equalsStoredValue = [verifiedKey isEqualToData:[[TSStorageManager sharedManager] identityKeyForRecipientId:self.uniqueId]];
        
        if (equalsStoredValue) {
            return YES;
        } else{
            verifiedKey = nil;
            return NO;
        }
        
    } else{
        return NO;
    }
}

- (void)setFingerPrintVerified:(BOOL)verified transaction:(YapDatabaseReadTransaction*)transaction{
    if (verified) {
        verifiedKey = [[TSStorageManager sharedManager] identityKeyForRecipientId:self.uniqueId];
    } else{
        verifiedKey = nil;
    }
}


@end
