//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWS2FAManager.h"
#import "OWSRequestFactory.h"
#import "TSNetworkManager.h"
#import "TSStorageManager.h"
#import "YapDatabaseConnection+OWS.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWS2FAManager_Collection = @"kOWS2FAManager_Collection";
NSString *const kOWS2FAManager_IsEnabledKey = @"kOWS2FAManager_IsEnabledKey";

@interface OWS2FAManager ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) TSNetworkManager *networkManager;

@end

#pragma mark -

@implementation OWS2FAManager

+ (instancetype)sharedManager
{
    static OWS2FAManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    TSNetworkManager *networkManager = [TSNetworkManager sharedManager];

    return [self initWithStorageManager:storageManager networkManager:networkManager];
}

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
                        networkManager:(TSNetworkManager *)networkManager
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssert(storageManager);
    OWSAssert(networkManager);

    _dbConnection = storageManager.newDatabaseConnection;
    _networkManager = networkManager;

    OWSSingletonAssert();

    return self;
}

- (BOOL)is2FAEnabled
{
    return [self.dbConnection boolForKey:kOWS2FAManager_IsEnabledKey
                            inCollection:kOWS2FAManager_Collection
                            defaultValue:NO];
}

- (void)setIs2FAEnabled:(BOOL)value
{
    [self.dbConnection setBool:value forKey:kOWS2FAManager_IsEnabledKey inCollection:kOWS2FAManager_Collection];
}

- (void)enable2FAWithPin:(NSString *)pin success:(nullable OWS2FASuccess)success failure:(nullable OWS2FAFailure)failure
{
    OWSAssert(pin.length > 0);
    OWSAssert(success);
    OWSAssert(failure);

    TSRequest *request = [OWSRequestFactory enable2FARequestWithPin:pin];
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            OWSAssertIsOnMainThread();

            [self setIs2FAEnabled:YES];

            if (success) {
                success();
            }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            OWSAssertIsOnMainThread();

            if (failure) {
                failure(error);
            }
        }];
}

- (void)disable2FAWithSuccess:(nullable OWS2FASuccess)success failure:(nullable OWS2FAFailure)failure
{
    TSRequest *request = [OWSRequestFactory disable2FARequest];
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            OWSAssertIsOnMainThread();

            [self setIs2FAEnabled:NO];

            if (success) {
                success();
            }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            OWSAssertIsOnMainThread();

            if (failure) {
                failure(error);
            }
        }];
}

@end

NS_ASSUME_NONNULL_END
