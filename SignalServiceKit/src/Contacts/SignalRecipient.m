//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalRecipient.h"
#import "OWSIdentityManager.h"
#import "TSAccountManager.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@implementation SignalRecipient

+ (NSString *)collection {
    return @"SignalRecipient";
}

- (instancetype)initWithTextSecureIdentifier:(NSString *)textSecureIdentifier
                                       relay:(nullable NSString *)relay
{
    self = [super initWithUniqueId:textSecureIdentifier];
    if (!self) {
        return self;
    }

    OWSAssert([TSAccountManager localNumber].length > 0);
    if ([[TSAccountManager localNumber] isEqualToString:textSecureIdentifier]) {
        // Default to no devices.
        //
        // This instance represents our own account and is used for sending
        // sync message to linked devices.  We shouldn't have any linked devices
        // yet when we create the "self" SignalRecipient, and we don't need to
        // send sync messages to the primary - we ARE the primary.
        _devices = [NSMutableOrderedSet new];
    } else {
        // Default to sending to just primary device.
        //
        // OWSMessageSender will correct this if it is wrong the next time
        // we send a message to this recipient.
        _devices = [NSMutableOrderedSet orderedSetWithObject:@(1)];
    }

    _relay = [relay isEqualToString:@""] ? nil : relay;

    return self;
}

+ (nullable instancetype)recipientWithTextSecureIdentifier:(NSString *)textSecureIdentifier
                                           withTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [self fetchObjectWithUniqueID:textSecureIdentifier transaction:transaction];
}

+ (nullable instancetype)recipientWithTextSecureIdentifier:(NSString *)textSecureIdentifier
{
    __block SignalRecipient *recipient;
    [self.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        recipient = [self recipientWithTextSecureIdentifier:textSecureIdentifier withTransaction:transaction];
    }];
    return recipient;
}

// TODO This method should probably live on the TSAccountManager rather than grabbing a global singleton.
+ (instancetype)selfRecipient
{
    SignalRecipient *myself = [self recipientWithTextSecureIdentifier:[TSAccountManager localNumber]];
    if (!myself) {
        myself = [[self alloc] initWithTextSecureIdentifier:[TSAccountManager localNumber] relay:nil];
    }
    return myself;
}

- (NSMutableOrderedSet *)devices {
    return [_devices copy];
}

- (void)addDevices:(NSSet *)set {
    [self checkDevices];
    [_devices unionSet:set];
}

- (void)removeDevices:(NSSet *)set {
    [self checkDevices];
    [_devices minusSet:set];
}

- (void)checkDevices {
    if (_devices == nil || ![_devices isKindOfClass:[NSMutableOrderedSet class]]) {
        _devices = [NSMutableOrderedSet orderedSetWithObject:[NSNumber numberWithInt:1]];
    }
}

- (BOOL)supportsVoice
{
    return YES;
}

- (BOOL)supportsWebRTC
{
    return YES;
}

- (NSString *)recipientId
{
    return self.uniqueId;
}

- (NSComparisonResult)compare:(SignalRecipient *)other
{
    return [self.recipientId compare:other.recipientId];
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [super saveWithTransaction:transaction];

    DDLogVerbose(@"%@ saved signal recipient: %@", self.logTag, self.recipientId);
}

@end

NS_ASSUME_NONNULL_END
