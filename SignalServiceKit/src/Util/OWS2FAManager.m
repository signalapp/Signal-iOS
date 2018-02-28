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

- (void)enable2FAWithPin:(NSString *)pin success:(OWS2FASuccess)success failure:(OWS2FAFailure)failure
{
    OWSAssert(pin.length > 0);
    OWSAssert(success);
    OWSAssert(failure);

    TSRequest *request = [OWSRequestFactory enable2FARequestWithPin:pin];
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            success();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            failure(error);
        }];
}

- (void)disable2FAWithSuccess:(OWS2FASuccess)success failure:(OWS2FAFailure)failure
{
    OWSAssert(success);
    OWSAssert(failure);

    TSRequest *request = [OWSRequestFactory disable2FARequest];
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            success();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            failure(error);
        }];
}

@end

NS_ASSUME_NONNULL_END
