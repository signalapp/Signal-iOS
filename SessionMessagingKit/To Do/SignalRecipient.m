//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalRecipient.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "TSAccountManager.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@interface SignalRecipient ()

@property (nonatomic) NSOrderedSet *devices;

@end

#pragma mark -

@implementation SignalRecipient

#pragma mark - Dependencies

- (id<ProfileManagerProtocol>)profileManager
{
    return SSKEnvironment.shared.profileManager;
}

- (TSAccountManager *)tsAccountManager
{
    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark -

+ (instancetype)getOrBuildUnsavedRecipientForRecipientId:(NSString *)recipientId
                                             transaction:(YapDatabaseReadTransaction *)transaction
{
    SignalRecipient *_Nullable recipient =
        [self registeredRecipientForRecipientId:recipientId mustHaveDevices:NO transaction:transaction];
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
   
    _devices = [NSOrderedSet orderedSetWithObject:@(1)];

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

    // Since we use device count to determine whether a user is registered or not,
    // ensure the local user always has at least *this* device.
    if (![_devices containsObject:@(1)]) {
        if ([self.uniqueId isEqualToString:self.tsAccountManager.localNumber]) {
            [self addDevices:[NSSet setWithObject:@(1)]];
        }
    }

    return self;
}

+ (nullable instancetype)registeredRecipientForRecipientId:(NSString *)recipientId
                                           mustHaveDevices:(BOOL)mustHaveDevices
                                               transaction:(YapDatabaseReadTransaction *)transaction
{
    SignalRecipient *_Nullable signalRecipient = [self fetchObjectWithUniqueID:recipientId transaction:transaction];
    if (mustHaveDevices && signalRecipient.devices.count < 1) {
        return nil;
    }
    return signalRecipient;
}

- (void)addDevices:(NSSet *)devices
{
    NSMutableOrderedSet *updatedDevices = [self.devices mutableCopy];
    [updatedDevices unionSet:devices];
    self.devices = [updatedDevices copy];
}

- (void)removeDevices:(NSSet *)devices
{
    NSMutableOrderedSet *updatedDevices = [self.devices mutableCopy];
    [updatedDevices minusSet:devices];
    self.devices = [updatedDevices copy];
}

- (void)updateRegisteredRecipientWithDevicesToAdd:(nullable NSArray *)devicesToAdd
                                  devicesToRemove:(nullable NSArray *)devicesToRemove
                                      transaction:(YapDatabaseReadWriteTransaction *)transaction {
    // Add before we remove, since removeDevicesFromRecipient:...
    // can markRecipientAsUnregistered:... if the recipient has
    // no devices left.
    if (devicesToAdd.count > 0) {
        [self addDevicesToRegisteredRecipient:[NSSet setWithArray:devicesToAdd] transaction:transaction];
    }
    if (devicesToRemove.count > 0) {
        [self removeDevicesFromRecipient:[NSSet setWithArray:devicesToRemove] transaction:transaction];
    }
}

- (void)addDevicesToRegisteredRecipient:(NSSet *)devices transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self reloadWithTransaction:transaction];
    [self addDevices:devices];
    [self saveWithTransaction_internal:transaction];
}

- (void)removeDevicesFromRecipient:(NSSet *)devices transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self reloadWithTransaction:transaction ignoreMissing:YES];
    [self removeDevices:devices];
    [self saveWithTransaction_internal:transaction];
}

- (NSString *)recipientId
{
    return self.uniqueId;
}

- (NSComparisonResult)compare:(SignalRecipient *)other
{
    return [self.recipientId compare:other.recipientId];
}

- (void)removeWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    // We need to distinguish between "users we know to be unregistered" and
    // "users whose registration status is unknown".  The former correspond to
    // instances of SignalRecipient with no devices.  The latter do not
    // correspond to an instance of SignalRecipient in the database (although
    // they may correspond to an "unsaved" instance of SignalRecipient built
    // by getOrBuildUnsavedRecipientForRecipientId.

    [super removeWithTransaction:transaction];
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    // We only want to mutate the persisted SignalRecipients in the database
    // using other methods of this class, e.g. markRecipientAsRegistered...
    // to create, addDevices and removeDevices to mutate.  We're trying to
    // be strict about using persisted SignalRecipients as a cache to
    // reflect "last known registration status".  Forcing our codebase to
    // use those methods helps ensure that we update the cache deliberately.

    [self saveWithTransaction_internal:transaction];
}

- (void)saveWithTransaction_internal:(YapDatabaseReadWriteTransaction *)transaction
{
    [super saveWithTransaction:transaction];
}

+ (BOOL)isRegisteredRecipient:(NSString *)recipientId transaction:(YapDatabaseReadTransaction *)transaction
{
    return nil != [self registeredRecipientForRecipientId:recipientId mustHaveDevices:YES transaction:transaction];
}

+ (SignalRecipient *)markRecipientAsRegisteredAndGet:(NSString *)recipientId
                                         transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    SignalRecipient *_Nullable instance =
        [self registeredRecipientForRecipientId:recipientId mustHaveDevices:YES transaction:transaction];

    if (!instance) {

        instance = [[self alloc] initWithTextSecureIdentifier:recipientId];
        [instance saveWithTransaction_internal:transaction];
    }
    return instance;
}

+ (void)markRecipientAsRegistered:(NSString *)recipientId
                         deviceId:(UInt32)deviceId
                      transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    SignalRecipient *recipient = [self markRecipientAsRegisteredAndGet:recipientId transaction:transaction];
    if (![recipient.devices containsObject:@(deviceId)]) {

        [recipient addDevices:[NSSet setWithObject:@(deviceId)]];
        [recipient saveWithTransaction_internal:transaction];
    }
}

+ (void)markRecipientAsUnregistered:(NSString *)recipientId transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    SignalRecipient *instance = [self getOrBuildUnsavedRecipientForRecipientId:recipientId
                                                                   transaction:transaction];
    if (instance.devices.count > 0) {
        [instance removeDevices:instance.devices.set];
    }
    [instance saveWithTransaction_internal:transaction];
}

@end

NS_ASSUME_NONNULL_END
