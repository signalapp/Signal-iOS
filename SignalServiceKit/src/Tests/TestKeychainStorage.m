//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TestKeychainStorage.h"
#import "NSData+OWS.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation TestKeychainStorage

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.dataMap = [NSMutableDictionary new];

    return self;
}

- (NSString *_Nullable)stringForKey:(NSString *)key
                            service:(NSString *)service
                              error:(NSError *_Nullable *_Nullable)error
{
    OWSAssert(error);
    OWSAssert(key.length > 0);
    OWSAssert(service.length > 0);

    *error = nil;

    NSString *mapKey = [NSString stringWithFormat:@"%@-%@", service, key];
    NSData *_Nullable data = self.dataMap[mapKey];
    if (!data) {
        NSLog(@"stringForKey:%@ service:%@ -> nil", key, service);
        return nil;
    }
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSLog(@"stringForKey:%@ service:%@ -> %@", key, service, string);
    return string;
}

- (BOOL)setWithString:(NSString *)string
               forKey:(NSString *)key
              service:(NSString *)service
                error:(NSError *_Nullable *_Nullable)error
{
    OWSAssert(error);
    OWSAssert(key.length > 0);
    OWSAssert(service.length > 0);

    *error = nil;

    NSLog(@"setWithString:%@ service:%@ -> %@", key, service, string);

    NSString *mapKey = [NSString stringWithFormat:@"%@-%@", service, key];
    self.dataMap[mapKey] = [string dataUsingEncoding:NSUTF8StringEncoding];
    return YES;
}

- (NSData *_Nullable)dataForKey:(NSString *)key service:(NSString *)service error:(NSError *_Nullable *_Nullable)error
{
    OWSAssert(error);
    OWSAssert(key.length > 0);
    OWSAssert(service.length > 0);

    *error = nil;

    NSString *mapKey = [NSString stringWithFormat:@"%@-%@", service, key];
    NSData *_Nullable data = self.dataMap[mapKey];
    NSLog(@"dataForKey:%@ service:%@ -> %@", key, service, data.hexadecimalString);
    return data;
}

- (BOOL)setWithData:(NSData *)data
             forKey:(NSString *)key
            service:(NSString *)service
              error:(NSError *_Nullable *_Nullable)error
{
    OWSAssert(error);
    OWSAssert(key.length > 0);
    OWSAssert(service.length > 0);

    *error = nil;

    NSLog(@"setWithData:%@ service:%@ -> %@", key, service, data.hexadecimalString);

    NSString *mapKey = [NSString stringWithFormat:@"%@-%@", service, key];
    self.dataMap[mapKey] = data;
    return YES;
}

- (BOOL)removeWithKey:(NSString *)key service:(NSString *)service error:(NSError *_Nullable *_Nullable)error
{
    OWSAssert(error);
    OWSAssert(key.length > 0);
    OWSAssert(service.length > 0);

    *error = nil;

    NSLog(@"removeWithKey:%@ service:%@", key, service);

    NSString *mapKey = [NSString stringWithFormat:@"%@-%@", service, key];
    [self.dataMap removeObjectForKey:mapKey];
    return YES;
}

@end

NS_ASSUME_NONNULL_END
