//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalRecipient.h"
#import "TSAccountManager.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@interface SignalRecipient ()

@property (nonatomic) NSOrderedSet *devices;

@end

#pragma mark -

@implementation SignalRecipient

+ (instancetype)getOrBuildUnsavedRecipientForRecipientId:(NSString *)recipientId
                                             transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(recipientId.length > 0);
    
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

    OWSAssertDebug([TSAccountManager localNumber].length > 0);
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
        OWSFailDebug(@"self as recipient device");
    }

    return self;
}


+ (nullable instancetype)registeredRecipientForRecipientId:(NSString *)recipientId
                                               transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(recipientId.length > 0);

    return [self fetchObjectWithUniqueID:recipientId transaction:transaction];
}

- (void)addDevices:(NSSet *)devices
{
    OWSAssertDebug(devices.count > 0);
    
    if ([self.uniqueId isEqual:[TSAccountManager localNumber]] && [devices containsObject:@(1)]) {
        OWSFailDebug(@"adding self as recipient device");
        return;
    }

    NSMutableOrderedSet *updatedDevices = [self.devices mutableCopy];
    [updatedDevices unionSet:devices];
    self.devices = [updatedDevices copy];
}

- (void)removeDevices:(NSSet *)devices
{
    OWSAssertDebug(devices.count > 0);

    NSMutableOrderedSet *updatedDevices = [self.devices mutableCopy];
    [updatedDevices minusSet:devices];
    self.devices = [updatedDevices copy];
}

- (void)addDevicesToRegisteredRecipient:(NSSet *)devices transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(devices.count > 0);
    
    [self addDevices:devices];

    SignalRecipient *latest =
        [SignalRecipient markRecipientAsRegisteredAndGet:self.recipientId transaction:transaction];

    if ([devices isSubsetOfSet:latest.devices.set]) {
        return;
    }
    OWSLogDebug(@"adding devices: %@, to recipient: %@", devices, latest.recipientId);

    [latest addDevices:devices];
    [latest saveWithTransaction_internal:transaction];
}

- (void)removeDevicesFromRecipient:(NSSet *)devices transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(devices.count > 0);

    [self removeDevices:devices];

    SignalRecipient *_Nullable latest =
        [SignalRecipient registeredRecipientForRecipientId:self.recipientId transaction:transaction];

    if (!latest) {
        return;
    }
    if (![devices intersectsSet:latest.devices.set]) {
        return;
    }
    OWSLogDebug(@"removing devices: %@, from registered recipient: %@", devices, latest.recipientId);

    [latest removeDevices:devices];
    [latest saveWithTransaction_internal:transaction];
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
    // We only want to mutate the persisted SignalRecipients in the database
    // using other methods of this class, e.g. markRecipientAsRegistered...
    // to create, addDevices and removeDevices to mutate.  We're trying to
    // be strict about using persisted SignalRecipients as a cache to
    // reflect "last known registration status".  Forcing our codebase to
    // use those methods helps ensure that we update the cache deliberately.
    OWSFailDebug(@"Don't call saveWithTransaction from outside this class.");

    [self saveWithTransaction_internal:transaction];
}

- (void)saveWithTransaction_internal:(YapDatabaseReadWriteTransaction *)transaction
{
    [super saveWithTransaction:transaction];

    OWSLogVerbose(@"saved signal recipient: %@", self.recipientId);
}

+ (BOOL)isRegisteredRecipient:(NSString *)recipientId transaction:(YapDatabaseReadTransaction *)transaction
{
    SignalRecipient *_Nullable instance = [self registeredRecipientForRecipientId:recipientId transaction:transaction];
    return instance != nil;
}

+ (SignalRecipient *)markRecipientAsRegisteredAndGet:(NSString *)recipientId
                                         transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(recipientId.length > 0);

    SignalRecipient *_Nullable instance = [self registeredRecipientForRecipientId:recipientId transaction:transaction];

    if (!instance) {
        OWSLogDebug(@"creating recipient: %@", recipientId);

        instance = [[self alloc] initWithTextSecureIdentifier:recipientId];
        [instance saveWithTransaction_internal:transaction];
    }
    return instance;
}

+ (void)markRecipientAsRegistered:(NSString *)recipientId
                         deviceId:(UInt32)deviceId
                      transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(recipientId.length > 0);

    SignalRecipient *recipient = [self markRecipientAsRegisteredAndGet:recipientId transaction:transaction];
    if (![recipient.devices containsObject:@(deviceId)]) {
        OWSLogDebug(@"Adding device %u to existing recipient.", (unsigned int)deviceId);

        [recipient addDevices:[NSSet setWithObject:@(deviceId)]];
        [recipient saveWithTransaction_internal:transaction];
    }
}

+ (void)removeUnregisteredRecipient:(NSString *)recipientId transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(recipientId.length > 0);

    SignalRecipient *_Nullable instance = [self registeredRecipientForRecipientId:recipientId transaction:transaction];
    if (!instance) {
        return;
    }
    OWSLogDebug(@"removing recipient: %@", recipientId);
    [instance removeWithTransaction:transaction];
}

@end

NS_ASSUME_NONNULL_END
