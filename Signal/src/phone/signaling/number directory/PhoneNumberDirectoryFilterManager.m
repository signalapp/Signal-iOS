#import "PhoneNumberDirectoryFilterManager.h"

#import "ContactsManager.h"
#import "Cryptography.h"
#import "Environment.h"
#import "NotificationManifest.h"
#import "PreferencesUtil.h"
#import "RPServerRequestsManager.h"
#import "SignalUtil.h"
#import "ThreadManager.h"
#import "TSContactsIntersectionRequest.h"
#import "TSStorageManager.h"
#import "TSRecipient.h"
#import "Util.h"

#define MINUTE (60.0)
#define HOUR (MINUTE*60.0)

#define DIRECTORY_UPDATE_TIMEOUT_PERIOD (1.0*MINUTE)
#define DIRECTORY_UPDATE_RETRY_PERIOD (1.0*HOUR)

@implementation PhoneNumberDirectoryFilterManager {
@private TOCCancelTokenSource* currentUpdateLifetime;
}

- (id)init {
    if (self = [super init]) {
        phoneNumberDirectoryFilter = PhoneNumberDirectoryFilter.phoneNumberDirectoryFilterDefault;
    }
    return self;
}
- (void)startUntilCancelled:(TOCCancelToken*)cancelToken {
    lifetimeToken = cancelToken;
    
    phoneNumberDirectoryFilter = [Environment.preferences tryGetSavedPhoneNumberDirectory];
    if (phoneNumberDirectoryFilter == nil) {
        phoneNumberDirectoryFilter = PhoneNumberDirectoryFilter.phoneNumberDirectoryFilterDefault;
    }
    
    [self scheduleUpdate];
}

- (PhoneNumberDirectoryFilter*)getCurrentFilter {
    @synchronized(self) {
        return phoneNumberDirectoryFilter;
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
        if (Environment.isRedPhoneRegistered) {
            [self updateRedPhone];
            
        }
    };
    
    [currentUpdateLifetime cancel];
    currentUpdateLifetime = [TOCCancelTokenSource new];
    [lifetimeToken whenCancelledDo:^{ [currentUpdateLifetime cancel]; }];
    [TimeUtil scheduleRun:doUpdate
                       at:date
                onRunLoop:[ThreadManager normalLatencyThreadRunLoop]
          unlessCancelled:currentUpdateLifetime.token];
}


- (void) updateRedPhone {
    
    [[RPServerRequestsManager sharedInstance] performRequest:[RPAPICall fetchBloomFilter] success:^(NSURLSessionDataTask *task, id responseObject) {
        PhoneNumberDirectoryFilter *directory = [PhoneNumberDirectoryFilter phoneNumberDirectoryFilterFromURLResponse:(NSHTTPURLResponse*)task.response body:responseObject];
        
        @synchronized(self) {
            phoneNumberDirectoryFilter = directory;
        }
        
        [Environment.preferences setSavedPhoneNumberDirectory:directory];
        [self updateTextSecureWithRedPhoneSucces:YES];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        DDLogError(@"Error to fetch contact interesection: %@", error.debugDescription);
        NSString* desc = [NSString stringWithFormat:@"Failed to retrieve directory. Retrying in %f hours.",
                          DIRECTORY_UPDATE_RETRY_PERIOD/HOUR];
        Environment.errorNoter(desc, error, false);
        BloomFilter* filter = [phoneNumberDirectoryFilter bloomFilter];
        NSDate* retryDate = [NSDate dateWithTimeInterval:DIRECTORY_UPDATE_RETRY_PERIOD
                                               sinceDate:[NSDate date]];
        @synchronized(self) {
            phoneNumberDirectoryFilter = [PhoneNumberDirectoryFilter phoneNumberDirectoryFilterWithBloomFilter:filter
                                                                                             andExpirationDate:retryDate];
        }
        
        [self updateTextSecureWithRedPhoneSucces:NO];
    }];
}

- (void)updateTextSecureWithRedPhoneSucces:(BOOL)redPhoneSuccess {
    NSArray *allContacts = [[[Environment getCurrent] contactsManager] allContacts];
    
    NSMutableDictionary *contactsByPhoneNumber = [NSMutableDictionary dictionary];
    NSMutableDictionary *phoneNumbersByHashes  = [NSMutableDictionary dictionary];
    
    for (Contact *contact in allContacts) {
        for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
            [phoneNumbersByHashes setObject:phoneNumber.toE164 forKey:[Cryptography truncatedSHA1Base64EncodedWithoutPadding:phoneNumber.toE164]];
            [contactsByPhoneNumber setObject:contact forKey:phoneNumber.toE164];
        }
    }
    
    NSArray *hashes = [phoneNumbersByHashes allKeys];
    
    TSRequest *request = [[TSContactsIntersectionRequest alloc]initWithHashesArray:hashes];
    
    [[TSNetworkManager sharedManager] queueAuthenticatedRequest:request success:^(NSURLSessionDataTask *tsTask, id responseDict) {
        NSMutableArray      *tsIdentifiers      = [NSMutableArray array];
        NSMutableDictionary *relayForIdentifier = [NSMutableDictionary dictionary];
        NSArray *contactsArray                  = [(NSDictionary*)responseDict objectForKey:@"contacts"];
        
        if (contactsArray) {
            for (NSDictionary *dict in contactsArray) {
                NSString *hash = [dict objectForKey:@"token"];
                
                if (hash) {
                    [tsIdentifiers addObject:[phoneNumbersByHashes objectForKey:hash]];
                    
                    NSString *relay = [dict objectForKey:@"relay"];
                    if (relay) {
                        [relayForIdentifier setObject:relay forKey:[phoneNumbersByHashes objectForKey:hash]];
                    }
                }
            }
        }
        
        [[TSStorageManager sharedManager].databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            for (NSString *identifier in tsIdentifiers) {
                TSRecipient *recipient = [TSRecipient recipientWithTextSecureIdentifier:identifier withTransaction:transaction];
                if (!recipient) {
                    NSString *relay = [relayForIdentifier objectForKey:recipient];
                    recipient = [[TSRecipient alloc] initWithTextSecureIdentifier:identifier relay:relay];
                }
                [recipient saveWithTransaction:transaction];
            }
        }];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_DIRECTORY_WAS_UPDATED object:nil];
        [self scheduleUpdate];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_DIRECTORY_FAILED object:nil];
    }];
}


@end
