//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalRecipient.h"
#import "TSAccountManager.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@interface SignalRecipient ()

@property NSOrderedSet *devices;

@end

#pragma mark -

@implementation SignalRecipient

+ (NSString *)collection {
    return @"SignalRecipient";
}

+ (SignalRecipient *)ensureRecipientExistsWithRecipientId:(NSString *)recipientId
                                              transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    SignalRecipient *_Nullable recipient =
        [self recipientWithTextSecureIdentifier:recipientId withTransaction:transaction];
    if (recipient) {
        return recipient;
    }

    DDLogDebug(@"%@ creating recipient: %@", self.logTag, recipientId);

    recipient = [[self alloc] initWithTextSecureIdentifier:recipientId];
    [recipient saveWithTransaction:transaction];
    return recipient;
}

+ (void)ensureRecipientExistsWithRecipientId:(NSString *)recipientId
                                    deviceId:(UInt32)deviceId
                                 transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    SignalRecipient *_Nullable existingRecipient =
        [self recipientWithTextSecureIdentifier:recipientId withTransaction:transaction];
    if (!existingRecipient) {
        DDLogDebug(@"%@ in %s creating recipient: %@, with deviceId: %u",
            self.logTag,
            __PRETTY_FUNCTION__,
            recipientId,
            (unsigned int)deviceId);

        SignalRecipient *newRecipient = [[self alloc] initWithTextSecureIdentifier:recipientId];
        [newRecipient addDevices:[NSSet setWithObject:@(deviceId)]];
        [newRecipient saveWithTransaction:transaction];

        return;
    }

    if (![existingRecipient.devices containsObject:@(deviceId)]) {
        DDLogDebug(@"%@ in %s adding device %u to existing recipient.",
            self.logTag,
            __PRETTY_FUNCTION__,
            (unsigned int)deviceId);

        [existingRecipient addDevices:[NSSet setWithObject:@(deviceId)]];
        [existingRecipient saveWithTransaction:transaction];
    }
}

- (instancetype)initWithTextSecureIdentifier:(NSString *)textSecureIdentifier
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
        _devices = [NSOrderedSet new];
    } else {
        // Default to sending to just primary device.
        //
        // OWSMessageSender will correct this if it is wrong the next time
        // we send a message to this recipient.
        _devices = [NSOrderedSet orderedSetWithObject:@(1)];
    }

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_devices == nil) {
        _devices = [NSOrderedSet new];
    }

    if ([self.uniqueId isEqual:[TSAccountManager localNumber]] && [self.devices containsObject:@(1)]) {
        OWSFail(@"%@ in %s self as recipient device", self.logTag, __PRETTY_FUNCTION__);
    }

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
        myself = [[self alloc] initWithTextSecureIdentifier:[TSAccountManager localNumber]];
    }
    return myself;
}

- (void)addDevices:(NSSet *)set
{
    if ([self.uniqueId isEqual:[TSAccountManager localNumber]] && [set containsObject:@(1)]) {
        OWSFail(@"%@ in %s adding self as recipient device", self.logTag, __PRETTY_FUNCTION__);
        return;
    }

    NSMutableOrderedSet *updatedDevices = [self.devices mutableCopy];
    [updatedDevices unionSet:set];

    self.devices = [updatedDevices copy];
}

- (void)removeDevices:(NSSet *)set
{
    NSMutableOrderedSet *updatedDevices = [self.devices mutableCopy];
    [updatedDevices minusSet:set];

    self.devices = [updatedDevices copy];
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
