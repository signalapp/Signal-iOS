//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalRecipient.h"
#import "TSAccountManager.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@interface SignalRecipient ()

@property (nonatomic) BOOL mayBeUnregistered;

@property (nonatomic) NSOrderedSet *devices;

@end

#pragma mark -

@implementation SignalRecipient

+ (NSString *)collection {
    return @"SignalRecipient";
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSFail(@"%@ We should no longer remove SignalRecipients.", self.logTag);

    [super removeWithTransaction:transaction];
}

+ (instancetype)getOrCreatedUnsavedRecipientForRecipientId:(NSString *)recipientId
                                               transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(transaction);
    OWSAssert(recipientId.length > 0);
    
    SignalRecipient *_Nullable recipient = [self registeredRecipientForRecipientId:recipientId transaction:transaction];
    if (!recipient) {
        recipient = [[self alloc] initWithTextSecureIdentifier:recipientId];
    }
    return recipient;
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


+ (nullable instancetype)registeredRecipientForRecipientId:(NSString *)recipientId
                                               transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(transaction);
    OWSAssert(recipientId.length > 0);

    SignalRecipient *_Nullable instance = [self recipientForRecipientId:recipientId transaction:transaction];
    if (instance && !instance.mayBeUnregistered) {
        return instance;
    } else {
        return nil;
    }
}

+ (nullable instancetype)recipientForRecipientId:(NSString *)recipientId
                                     transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(transaction);
    OWSAssert(recipientId.length > 0);

    return [self fetchObjectWithUniqueID:recipientId transaction:transaction];
}

+ (nullable instancetype)recipientForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    __block SignalRecipient *recipient;
    [self.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        recipient = [self recipientForRecipientId:recipientId transaction:transaction];
    }];
    return recipient;
}

// TODO This method should probably live on the TSAccountManager rather than grabbing a global singleton.
+ (instancetype)selfRecipient
{
    SignalRecipient *myself = [self recipientForRecipientId:[TSAccountManager localNumber]];
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

    NSMutableOrderedSet *updatedDevices = (self.devices
                                           ? [self.devices mutableCopy]
                                           : [NSMutableOrderedSet new]);
    [updatedDevices unionSet:set];
    self.devices = [updatedDevices copy];
}

- (void)removeDevices:(NSSet *)set
{
    NSMutableOrderedSet *updatedDevices = (self.devices
                                           ? [self.devices mutableCopy]
                                           : [NSMutableOrderedSet new]);
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

+ (BOOL)isRegisteredSignalAccount:(NSString *)recipientId
{
    __block BOOL result;
    [self.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        result = [self isRegisteredSignalAccount:recipientId transaction:transaction];
    }];
    return result;
}

+ (BOOL)isRegisteredSignalAccount:(NSString *)recipientId transaction:(YapDatabaseReadTransaction *)transaction
{
    SignalRecipient *_Nullable instance = [self recipientForRecipientId:recipientId transaction:transaction];
    return (instance && !instance.mayBeUnregistered);
}

+ (SignalRecipient *)markAccountAsRegistered:(NSString *)recipientId transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);
    OWSAssert(recipientId.length > 0);

    SignalRecipient *_Nullable instance = [self recipientForRecipientId:recipientId transaction:transaction];

    if (!instance) {
        DDLogDebug(@"%@ creating recipient: %@", self.logTag, recipientId);

        instance = [[self alloc] initWithTextSecureIdentifier:recipientId];
        [instance saveWithTransaction:transaction];
    } else if (instance.mayBeUnregistered) {
        instance.mayBeUnregistered = NO;
        [instance saveWithTransaction:transaction];
    }
    return instance;
}

+ (void)markAccountAsRegistered:(NSString *)recipientId
                       deviceId:(UInt32)deviceId
                    transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);
    OWSAssert(recipientId.length > 0);

    SignalRecipient *recipient = [self markAccountAsRegistered:recipientId transaction:transaction];
    if (![recipient.devices containsObject:@(deviceId)]) {
        DDLogDebug(@"%@ in %s adding device %u to existing recipient.",
                   self.logTag,
                   __PRETTY_FUNCTION__,
                   (unsigned int)deviceId);
        
        [recipient addDevices:[NSSet setWithObject:@(deviceId)]];
        [recipient saveWithTransaction:transaction];
    }
}

+ (void)markAccountAsNotRegistered:(NSString *)recipientId transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssert(transaction);
    OWSAssert(recipientId.length > 0);

    SignalRecipient *_Nullable instance = [self recipientForRecipientId:recipientId transaction:transaction];
    if (!instance) {
        return;
    }
    if (instance.mayBeUnregistered) {
        return;
    }
    instance.mayBeUnregistered = YES;
    [instance saveWithTransaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
