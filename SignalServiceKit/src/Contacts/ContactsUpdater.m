//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ContactsUpdater.h"
#import "Contact.h"
#import "Cryptography.h"
#import "OWSError.h"
#import "OWSPrimaryStorage.h"
#import "OWSRequestFactory.h"
#import "PhoneNumber.h"
#import "TSNetworkManager.h"
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@implementation ContactsUpdater

+ (instancetype)sharedUpdater {
    static dispatch_once_t onceToken;
    static id sharedInstance = nil;
    dispatch_once(&onceToken, ^{
        sharedInstance = [self new];
    });
    return sharedInstance;
}


- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    return self;
}

- (nullable SignalRecipient *)synchronousLookup:(NSString *)identifier error:(NSError **)error
{
    OWSAssert(error);

    DDLogInfo(@"%@ %s %@", self.logTag, __PRETTY_FUNCTION__, identifier);

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    __block SignalRecipient *recipient;

    // Assigning to a pointer parameter within the block is not preventing the referenced error from being dealloc
    // Instead, we avoid ambiguity in ownership by assigning to a local __block variable ensuring the error will be
    // retained until our error parameter can take ownership.
    __block NSError *retainedError;
    [self lookupIdentifier:identifier
        success:^(SignalRecipient *fetchedRecipient) {
            recipient = fetchedRecipient;
            dispatch_semaphore_signal(sema);
        }
        failure:^(NSError *lookupError) {
            retainedError = lookupError;
            dispatch_semaphore_signal(sema);
        }];

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    *error = retainedError;
    return recipient;
}

- (void)lookupIdentifier:(NSString *)identifier
                 success:(void (^)(SignalRecipient *recipient))success
                 failure:(void (^)(NSError *error))failure
{
    // This should never happen according to nullability annotations... but IIRC it does. =/
    if (!identifier) {
        OWSFail(@"%@ Cannot lookup nil identifier", self.logTag);
        failure(OWSErrorWithCodeDescription(OWSErrorCodeInvalidMethodParameters, @"Cannot lookup nil identifier"));
        return;
    }
    
    [self contactIntersectionWithSet:[NSSet setWithObject:identifier]
                             success:^(NSSet<NSString *> *_Nonnull matchedIds) {
                                 if (matchedIds.count == 1) {
                                     success([SignalRecipient recipientWithTextSecureIdentifier:identifier]);
                                 } else {
                                     failure(OWSErrorMakeNoSuchSignalRecipientError());
                                 }
                             }
                             failure:failure];
}

- (void)lookupIdentifiers:(NSArray<NSString *> *)identifiers
                 success:(void (^)(NSArray<SignalRecipient *> *recipients))success
                 failure:(void (^)(NSError *error))failure
{
    if (identifiers.count < 1) {
        OWSFail(@"%@ Cannot lookup zero identifiers", self.logTag);
        failure(OWSErrorWithCodeDescription(OWSErrorCodeInvalidMethodParameters, @"Cannot lookup zero identifiers"));
        return;
    }

    [self contactIntersectionWithSet:[NSSet setWithArray:identifiers]
                             success:^(NSSet<NSString *> *_Nonnull matchedIds) {
                                 if (matchedIds.count > 0) {
                                     NSMutableArray<SignalRecipient *> *recipients = [NSMutableArray new];
                                     for (NSString *identifier in matchedIds) {
                                         [recipients addObject:[SignalRecipient recipientWithTextSecureIdentifier:identifier]];
                                     }
                                     success([recipients copy]);
                                 } else {
                                     failure(OWSErrorMakeNoSuchSignalRecipientError());
                                 }
                             }
                             failure:failure];
}

- (void)updateSignalContactIntersectionWithABContacts:(NSArray<Contact *> *)abContacts
                                              success:(void (^)(void))success
                                              failure:(void (^)(NSError *error))failure
{
    NSMutableSet<NSString *> *abPhoneNumbers = [NSMutableSet set];

    for (Contact *contact in abContacts) {
        for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
            [abPhoneNumbers addObject:phoneNumber.toE164];
        }
    }

    NSMutableSet *recipientIds = [NSMutableSet set];
    [OWSPrimaryStorage.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        NSArray *allRecipientKeys = [transaction allKeysInCollection:[SignalRecipient collection]];
        [recipientIds addObjectsFromArray:allRecipientKeys];
    }];

    NSMutableSet<NSString *> *allContacts = [[abPhoneNumbers setByAddingObjectsFromSet:recipientIds] mutableCopy];

    [self contactIntersectionWithSet:allContacts
                             success:^(NSSet<NSString *> *matchedIds) {
                                 [recipientIds minusSet:matchedIds];

                                 // Cleaning up unregistered identifiers
                                 [OWSPrimaryStorage.dbReadWriteConnection
                                     readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                         for (NSString *identifier in recipientIds) {
                                             SignalRecipient *recipient =
                                                 [SignalRecipient fetchObjectWithUniqueID:identifier
                                                                              transaction:transaction];

                                             [recipient removeWithTransaction:transaction];
                                         }
                                     }];

                                 DDLogInfo(@"%@ successfully intersected contacts.", self.logTag);
                                 success();
                             }
                             failure:failure];
}

- (void)contactIntersectionWithSet:(NSSet<NSString *> *)idSet
                           success:(void (^)(NSSet<NSString *> *matchedIds))success
                           failure:(void (^)(NSError *error))failure {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSMutableDictionary *phoneNumbersByHashes = [NSMutableDictionary dictionary];
      for (NSString *identifier in idSet) {
          [phoneNumbersByHashes setObject:identifier
                                   forKey:[Cryptography truncatedSHA1Base64EncodedWithoutPadding:identifier]];
      }
      NSArray *hashes = [phoneNumbersByHashes allKeys];

      TSRequest *request = [OWSRequestFactory contactsIntersectionRequestWithHashesArray:hashes];
      [[TSNetworkManager sharedManager] makeRequest:request
          success:^(NSURLSessionDataTask *tsTask, id responseDict) {
              NSMutableDictionary *attributesForIdentifier = [NSMutableDictionary dictionary];
              NSArray *contactsArray = [(NSDictionary *)responseDict objectForKey:@"contacts"];

              // Map attributes to phone numbers
              if (contactsArray) {
                  for (NSDictionary *dict in contactsArray) {
                      NSString *hash = [dict objectForKey:@"token"];
                      NSString *identifier = [phoneNumbersByHashes objectForKey:hash];

                      if (!identifier) {
                          DDLogWarn(@"%@ An interesecting hash wasn't found in the mapping.", self.logTag);
                          break;
                      }

                      [attributesForIdentifier setObject:dict forKey:identifier];
                  }
              }

              // Insert or update contact attributes
              [OWSPrimaryStorage.dbReadWriteConnection
                  readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                      for (NSString *identifier in attributesForIdentifier) {
                          SignalRecipient *recipient = [SignalRecipient recipientWithTextSecureIdentifier:identifier
                                                                                          withTransaction:transaction];
                          if (!recipient) {
                              recipient = [[SignalRecipient alloc] initWithTextSecureIdentifier:identifier relay:nil];
                          }

                          NSDictionary *attributes = [attributesForIdentifier objectForKey:identifier];

                          recipient.relay = attributes[@"relay"];

                          [recipient saveWithTransaction:transaction];
                      }
                  }];

              success([NSSet setWithArray:attributesForIdentifier.allKeys]);
          }
          failure:^(NSURLSessionDataTask *task, NSError *error) {
              if (!IsNSErrorNetworkFailure(error)) {
                  OWSProdError([OWSAnalyticsEvents contactsErrorContactsIntersectionFailed]);
              }

              NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
              if (response.statusCode == 413) {
                  failure(OWSErrorWithCodeDescription(
                      OWSErrorCodeContactsUpdaterRateLimit, @"Contacts Intersection Rate Limit"));
              } else {
                  failure(error);
              }
          }];
    });
}

@end

NS_ASSUME_NONNULL_END
