#import "PhoneNumberDirectoryFilterManager.h"

#import "Environment.h"
#import "NotificationManifest.h"
#import "PropertyListPreferences+Util.h"
#import "RPServerRequestsManager.h"
#import "HTTPRequest+SignalUtil.h"
#import "ThreadManager.h"
#import "Util.h"

#define MINUTE (60.0)
#define HOUR (MINUTE*60.0)

#define DIRECTORY_UPDATE_TIMEOUT_PERIOD (1.0*MINUTE)
#define DIRECTORY_UPDATE_RETRY_PERIOD (1.0*HOUR)

@interface PhoneNumberDirectoryFilterManager ()

@property (strong, nonatomic) PhoneNumberDirectoryFilter* phoneNumberDirectoryFilter;
@property (strong, nonatomic) TOCCancelToken* lifetimeToken;
@property (strong, nonatomic) TOCCancelTokenSource* currentUpdateLifetime;

@end

@implementation PhoneNumberDirectoryFilterManager

- (instancetype)init {
    return [super init];
}

- (PhoneNumberDirectoryFilter*)phoneNumberDirectoryFilter {
    if (!_phoneNumberDirectoryFilter)
        _phoneNumberDirectoryFilter = [PhoneNumberDirectoryFilter defaultFilter];
    return _phoneNumberDirectoryFilter;
}

- (void)startUntilCancelled:(TOCCancelToken*)cancelToken {
    self.lifetimeToken = cancelToken;
    
    self.phoneNumberDirectoryFilter = [Environment.preferences tryGetSavedPhoneNumberDirectory];
    
    [self scheduleUpdate];
}

- (PhoneNumberDirectoryFilter*)getCurrentFilter {
    @synchronized(self) {
        return self.phoneNumberDirectoryFilter;
    }
}

- (void)forceUpdate {
    [self scheduleUpdateAt:NSDate.date];
}

- (void)scheduleUpdate {
    return [self scheduleUpdateAt:self.getCurrentFilter.getExpirationDate];
}

- (void)scheduleUpdateAt:(NSDate*)date {
    void(^doUpdate)(void) = ^{
        if (Environment.isRegistered) {
            [self update];
        }
    };
    
    [self.currentUpdateLifetime cancel];
    self.currentUpdateLifetime = [[TOCCancelTokenSource alloc] init];
    [self.lifetimeToken whenCancelledDo:^{ [self.currentUpdateLifetime cancel]; }];
    [TimeUtil scheduleRun:doUpdate
                       at:date
                onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
          unlessCancelled:self.currentUpdateLifetime.token];
}

- (void)update {
    [[RPServerRequestsManager sharedInstance] performRequest:[RPAPICall fetchBloomFilter] success:^(NSURLSessionDataTask* task, NSData* responseObject) {
        PhoneNumberDirectoryFilter* directory = [[PhoneNumberDirectoryFilter alloc] initFromURLResponse:(NSHTTPURLResponse*)task.response
                                                                                                   body:responseObject];
        
        @synchronized(self) {
            self.phoneNumberDirectoryFilter = directory;
        }
        
        [Environment.preferences setSavedPhoneNumberDirectory:directory];
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_DIRECTORY_WAS_UPDATED object:nil];
        [self scheduleUpdate];
        
    } failure:^(NSURLSessionDataTask* task, NSError* error) {
        NSString* desc = [NSString stringWithFormat:@"Failed to retrieve directory. Retrying in %f hours.",
                          DIRECTORY_UPDATE_RETRY_PERIOD/HOUR];
        Environment.errorNoter(desc, error, false);
        BloomFilter* filter = self.phoneNumberDirectoryFilter.bloomFilter;
        NSDate* retryDate = [NSDate dateWithTimeInterval:DIRECTORY_UPDATE_RETRY_PERIOD
                                               sinceDate:[NSDate date]];
        @synchronized(self) {
            self.phoneNumberDirectoryFilter = [[PhoneNumberDirectoryFilter alloc] initWithBloomFilter:filter andExpirationDate:retryDate];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_DIRECTORY_FAILED object:nil];
    }];
}

@end
