//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSYapDatabaseObject.h"
#import <Mantle/MTLJSONAdapter.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDevice : TSYapDatabaseObject <MTLJSONSerializing>

@property (nonatomic, readonly) NSInteger deviceId;
@property (nullable, readonly) NSString *name;
@property (readonly) NSDate *createdAt;
@property (readonly) NSDate *lastSeenAt;

+ (instancetype)deviceFromJSONDictionary:(NSDictionary *)deviceAttributes error:(NSError **)error;

/**
 * Set local database of devices to `devices`.
 *
 * This will create missing devices, update existing devices, and delete stale devices.
 * @param devices
 */
+ (void)replaceAll:(NSArray<OWSDevice *> *)devices;

/**
 *
 * @param transaction
 * @return
 *   If the user has any linked devices (apart from the device this app is running on).
 */
+ (BOOL)hasSecondaryDevicesWithTransaction:(YapDatabaseReadTransaction *)transaction;

- (NSString *)displayName;
- (BOOL)isPrimaryDevice;

/**
 * Assign attributes to this device from another.
 *
 * @param other
 *  OWSDevice whose attributes to copy to this device
 * @return
 *  YES if any values on self changed, else NO
 */
- (BOOL)updateAttributesWithDevice:(OWSDevice *)other;

@end

NS_ASSUME_NONNULL_END
