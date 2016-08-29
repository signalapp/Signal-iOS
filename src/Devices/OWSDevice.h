//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSYapDatabaseObject.h"
#import <Mantle/MTLJSONAdapter.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSDevice : TSYapDatabaseObject <MTLJSONSerializing>

@property (nonatomic, readonly) NSInteger deviceId;
@property (nullable, nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSDate *createdAt;
@property (nonatomic, readonly) NSDate *lastSeenAt;

+ (instancetype)deviceFromJSONDictionary:(NSDictionary *)deviceAttributes error:(NSError **)error;
+ (NSArray<OWSDevice *> *)secondaryDevices;
+ (void)replaceAll:(NSArray<OWSDevice *> *)devices;

@end

NS_ASSUME_NONNULL_END
