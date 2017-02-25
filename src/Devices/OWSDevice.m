//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSDevice.h"
#import "NSDate+millisecondTimeStamp.h"
#import "OWSError.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"
#import <Mantle/MTLValueTransformer.h>

NS_ASSUME_NONNULL_BEGIN

static MTLValueTransformer *_millisecondTimestampToDateTransformer;
uint32_t const OWSDevicePrimaryDeviceId = 1;

@interface OWSDevice ()

@property NSString *name;
@property NSDate *createdAt;
@property NSDate *lastSeenAt;

@end

@implementation OWSDevice

@synthesize name = _name;

+ (instancetype)deviceFromJSONDictionary:(NSDictionary *)deviceAttributes error:(NSError **)error
{
    return [MTLJSONAdapter modelOfClass:[self class] fromJSONDictionary:deviceAttributes error:error];
}

+ (NSDictionary *)JSONKeyPathsByPropertyKey
{
    return @{
             @"createdAt": @"created",
             @"lastSeenAt": @"lastSeen",
             @"deviceId": @"id",
             @"name": @"name"
             };
}

+ (MTLValueTransformer *)createdAtJSONTransformer
{
    return self.millisecondTimestampToDateTransformer;
}

+ (MTLValueTransformer *)lastSeenAtJSONTransformer
{
    return self.millisecondTimestampToDateTransformer;
}

+ (void)replaceAll:(NSArray<OWSDevice *> *)currentDevices
{
    NSMutableArray<OWSDevice *> *existingDevices = [[self allObjectsInCollection] mutableCopy];
    for (OWSDevice *currentDevice in currentDevices) {
        NSUInteger existingDeviceIndex = [existingDevices indexOfObject:currentDevice];
        if (existingDeviceIndex == NSNotFound) {
            // New Device
            [currentDevice save];
        } else {
            OWSDevice *existingDevice = existingDevices[existingDeviceIndex];
            if ([existingDevice updateAttributesWithDevice:currentDevice]) {
                [existingDevice save];
            }
            [existingDevices removeObjectAtIndex:existingDeviceIndex];
        }
    }

    // Since we removed existing devices as we went, only stale devices remain
    for (OWSDevice *staleDevice in existingDevices) {
        [staleDevice remove];
    }
}

+ (MTLValueTransformer *)millisecondTimestampToDateTransformer
{
    if (!_millisecondTimestampToDateTransformer) {
        _millisecondTimestampToDateTransformer =
            [MTLValueTransformer transformerUsingForwardBlock:^id(id value, BOOL *success, NSError **error) {
                if ([value isKindOfClass:[NSNumber class]]) {
                    NSNumber *number = (NSNumber *)value;
                    NSDate *result = [NSDate ows_dateWithMillisecondsSince1970:[number longLongValue]];
                    if (result) {
                        *success = YES;
                        return result;
                    }
                }
                *success = NO;
                *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToDecodeJson,
                    [NSString stringWithFormat:@"unable to decode date from %@", value]);
                return nil;
            }
                reverseBlock:^id(id value, BOOL *success, NSError **error) {
                    if ([value isKindOfClass:[NSDate class]]) {
                        NSDate *date = (NSDate *)value;
                        NSNumber *result = [NSNumber numberWithLongLong:[NSDate ows_millisecondsSince1970ForDate:date]];
                        if (result) {
                            *success = YES;
                            return result;
                        }
                    }
                    *error = OWSErrorWithCodeDescription(OWSErrorCodeFailedToEncodeJson,
                        [NSString stringWithFormat:@"unable to encode date from %@", value]);
                    *success = NO;
                    return nil;
                }];
    }
    return _millisecondTimestampToDateTransformer;
}

+ (uint32_t)currentDeviceId
{
    // Someday it may be possible to have a non-primary iOS device, but for now
    // any iOS device must be the primary device.
    return OWSDevicePrimaryDeviceId;
}

- (BOOL)isPrimaryDevice
{
    return self.deviceId == OWSDevicePrimaryDeviceId;
}

- (NSString *)displayName
{
    if (self.name) {
        return self.name;
    }

    if (self.deviceId == OWSDevicePrimaryDeviceId) {
        return @"This Device";
    }
    return NSLocalizedString(@"UNNAMED_DEVICE", @"Label text in device manager for a device with no name");
}

- (BOOL)updateAttributesWithDevice:(OWSDevice *)other
{
    BOOL changed = NO;
    if (![self.lastSeenAt isEqual:other.lastSeenAt]) {
        self.lastSeenAt = other.lastSeenAt;
        changed = YES;
    }

    if (![self.createdAt isEqual:other.createdAt]) {
        self.createdAt = other.createdAt;
        changed = YES;
    }

    if (![self.name isEqual:other.name]) {
        self.name = other.name;
        changed = YES;
    }

    return changed;
}

+ (BOOL)hasSecondaryDevicesWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [self numberOfKeysInCollectionWithTransaction:transaction] > 1;
}

- (BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[OWSDevice class]]) {
        return NO;
    }

    return [self isEqualToDevice:(OWSDevice *)object];
}

- (BOOL)isEqualToDevice:(OWSDevice *)device
{
    return self.deviceId == device.deviceId;
}

@end

NS_ASSUME_NONNULL_END
