#import "PhoneNumberDirectoryFilterManager.h"
#import "Environment.h"
#import "PreferencesUtil.h"
#import "ThreadManager.h"
#import "Util.h"
#import "NotificationManifest.h"

#define MINUTE (60.0)
#define HOUR (MINUTE*60.0)

#define DIRECTORY_UPDATE_TIMEOUT_PERIOD (1.0*MINUTE)
#define DIRECTORY_UPDATE_RETRY_PERIOD (1.0*HOUR)

@implementation PhoneNumberDirectoryFilterManager {
@private CancelTokenSource* currentUpdateLifetime;
}

-(id) init {
	if (self = [super init]) {
		phoneNumberDirectoryFilter = [PhoneNumberDirectoryFilter phoneNumberDirectoryFilterDefault];
	}
	return self;
}
-(void) startUntilCancelled:(id<CancelToken>)cancelToken {
    lifetimeToken = cancelToken;
    
    phoneNumberDirectoryFilter = [[[Environment getCurrent] preferences] tryGetSavedPhoneNumberDirectory];
    if (phoneNumberDirectoryFilter == nil) {
        phoneNumberDirectoryFilter = [PhoneNumberDirectoryFilter phoneNumberDirectoryFilterDefault];
    }
    
    [self scheduleUpdate];
}

-(PhoneNumberDirectoryFilter*) getCurrentFilter {
    @synchronized(self) {
        return phoneNumberDirectoryFilter;
    }
}
-(void)forceUpdate {
    [self scheduleUpdateAt:NSDate.date];
}
-(void) scheduleUpdate {
    return [self scheduleUpdateAt:self.getCurrentFilter.getExpirationDate];
}
-(void) scheduleUpdateAt:(NSDate*)date {
    void(^doUpdate)(void) = ^{
        [self update];
    };
    
    [currentUpdateLifetime cancel];
    currentUpdateLifetime = [CancelTokenSource cancelTokenSource];
    [lifetimeToken whenCancelled:^{ [currentUpdateLifetime cancel]; }];
    [TimeUtil scheduleRun:doUpdate
                       at:date
                onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
          unlessCancelled:currentUpdateLifetime.getToken];
}

-(Future*) asyncQueryCurrentDirectory {
    CancellableOperationStarter startAwaitDirectoryOperation = ^(id<CancelToken> untilCancelledToken) {
		HttpRequest* directoryRequest = [HttpRequest httpRequestForPhoneNumberDirectoryFilter];

        Future* futureDirectoryResponse = [HttpManager asyncOkResponseFromMasterServer:directoryRequest
                                                                       unlessCancelled:untilCancelledToken
                                                                       andErrorHandler:[Environment errorNoter]];
        
        return [futureDirectoryResponse then:^(HttpResponse* response) {
			return [PhoneNumberDirectoryFilter phoneNumberDirectoryFilterFromHttpResponse:response];
		}];
    };
    
    return [AsyncUtil raceCancellableOperation:startAwaitDirectoryOperation
                                againstTimeout:DIRECTORY_UPDATE_TIMEOUT_PERIOD
                                untilCancelled:lifetimeToken];
}

-(PhoneNumberDirectoryFilter*) sameDirectoryWithRetryTimeout {
    BloomFilter* filter = [phoneNumberDirectoryFilter bloomFilter];
    NSDate* retryDate = [NSDate dateWithTimeInterval:DIRECTORY_UPDATE_RETRY_PERIOD
                                           sinceDate:[NSDate date]];
    return [PhoneNumberDirectoryFilter phoneNumberDirectoryFilterWithBloomFilter:filter
                                                               andExpirationDate:retryDate];
}
-(void) signalDirectoryQueryFailed:(id)failure {
    NSString* desc = [NSString stringWithFormat:@"Failed to retrieve directory. Retrying in %f hours.",
                      DIRECTORY_UPDATE_RETRY_PERIOD/HOUR];
    [Environment errorNoter](desc, failure, false);
}
-(Future*) asyncQueryCurrentDirectoryWithDefaultOnFail {
    Future* futureDirectory = [self asyncQueryCurrentDirectory];
    
    return [futureDirectory catch:^PhoneNumberDirectoryFilter*(id error) {
        [self signalDirectoryQueryFailed:error];
        return [self sameDirectoryWithRetryTimeout];
    }];
}

-(void) update {
    Future* eventualDirectory = [self asyncQueryCurrentDirectoryWithDefaultOnFail];
    
    [eventualDirectory thenDo:^(PhoneNumberDirectoryFilter* directory) {
        @synchronized(self) {
            phoneNumberDirectoryFilter = directory;
        }
        [[Environment preferences] setSavedPhoneNumberDirectory:directory];
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_DIRECTORY_WAS_UPDATED object:nil];
        [self scheduleUpdate];
    }];
}

@end
