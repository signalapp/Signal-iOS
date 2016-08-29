//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSDevice.h"
#import "NSDate+millisecondTimeStamp.h"
#import "OWSError.h"
#import "YapDatabaseConnection.h"
#import "YapDatabaseTransaction.h"
#import <Mantle/MTLValueTransformer.h>

NS_ASSUME_NONNULL_BEGIN

static MTLValueTransformer *_millisecondTimestampToDateTransformer;
static int const OWSDevicePrimaryDeviceId = 1;

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

+ (void)replaceAll:(NSArray<OWSDevice *> *)devices
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:[self collection]];
        for (OWSDevice *device in devices) {
            [device saveWithTransaction:transaction];
        }
    }];
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

+ (NSArray<OWSDevice *> *)secondaryDevices
{
    NSMutableArray<OWSDevice *> *devices = [NSMutableArray new];

    [self enumerateCollectionObjectsUsingBlock:^(id obj, BOOL *stop) {
        if ([obj isKindOfClass:[OWSDevice class]]) {
            OWSDevice *device = (OWSDevice *)obj;
            if (device.deviceId != OWSDevicePrimaryDeviceId) {
                [devices addObject:device];
            }
        }
    }];

    return [devices copy];
}

- (nullable NSString *)name
{
    if (_name) {
        return _name;
    }

    if (self.deviceId == OWSDevicePrimaryDeviceId) {
        return @"This Device";
    }
    return NSLocalizedString(@"UNNAMED_DEVICE", @"Label text in device manager for a device with no name");
}

@end

NS_ASSUME_NONNULL_END
