//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ContactsUpdater.h"
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

- (void)lookupIdentifier:(NSString *)recipientId
                 success:(void (^)(SignalRecipient *recipient))success
                 failure:(void (^)(NSError *error))failure
{
    OWSAssert(recipientId.length > 0);
    
    // This should never happen according to nullability annotations... but IIRC it does. =/
    if (!recipientId) {
        OWSFail(@"%@ Cannot lookup nil identifier", self.logTag);
        failure(OWSErrorWithCodeDescription(OWSErrorCodeInvalidMethodParameters, @"Cannot lookup nil identifier"));
        return;
    }
    
    NSSet *recipiendIds = [NSSet setWithObject:recipientId];
    [self contactIntersectionWithSet:recipiendIds
                             success:^(NSSet<SignalRecipient *> *recipients) {
                                 if (recipients.count > 0) {
                                     OWSAssert(recipients.count == 1);
                                     
                                     SignalRecipient *recipient = recipients.allObjects.firstObject;
                                     success(recipient);
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
                             success:^(NSSet<SignalRecipient *> *recipients) {
                                 if (recipients.count > 0) {
                                     success(recipients.allObjects);
                                 } else {
                                     failure(OWSErrorMakeNoSuchSignalRecipientError());
                                 }
                             }
                             failure:failure];
}

- (void)contactIntersectionWithSet:(NSSet<NSString *> *)recipientIdsToLookup
                           success:(void (^)(NSSet<SignalRecipient *> *recipients))success
                           failure:(void (^)(NSError *error))failure {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSMutableDictionary<NSString *, NSString *> *phoneNumbersByHashes = [NSMutableDictionary new];
      for (NSString *recipientId in recipientIdsToLookup) {
          NSString *hash = [Cryptography truncatedSHA1Base64EncodedWithoutPadding:recipientId];
           phoneNumbersByHashes[hash] = recipientId;
      }
      NSArray<NSString *> *hashes = [phoneNumbersByHashes allKeys];
        
      TSRequest *request = [OWSRequestFactory contactsIntersectionRequestWithHashesArray:hashes];
      [[TSNetworkManager sharedManager] makeRequest:request
          success:^(NSURLSessionDataTask *task, id responseDict) {
              NSMutableSet<NSString *> *registeredRecipientIds = [NSMutableSet new];
              
              if ([responseDict isKindOfClass:[NSDictionary class]]) {
                  NSArray<NSDictionary *> *_Nullable contactsArray = responseDict[@"contacts"];
                  if ([contactsArray isKindOfClass:[NSArray class]]) {
                      for (NSDictionary *contactDict in contactsArray) {
                          if (![contactDict isKindOfClass:[NSDictionary class]]) {
                              OWSProdLogAndFail(@"%@ invalid contact dictionary.", self.logTag);
                              continue;
                          }
                          NSString *_Nullable hash = contactDict[@"token"];
                          if (hash.length < 1) {
                              OWSProdLogAndFail(@"%@ contact missing hash.", self.logTag);
                              continue;
                          }
                          NSString *_Nullable recipientId = phoneNumbersByHashes[hash];
                          if (recipientId.length < 1) {
                              OWSProdLogAndFail(@"%@ An intersecting hash wasn't found in the mapping.", self.logTag);
                              continue;
                          }
                          if (![recipientIdsToLookup containsObject:recipientId]) {
                              OWSProdLogAndFail(@"%@ Intersection response included unexpected recipient.", self.logTag);
                              continue;
                          }
                          [registeredRecipientIds addObject:recipientId];
                      }
                  }
              }
              
              NSMutableSet<SignalRecipient *> *recipients = [NSMutableSet new];
              [OWSPrimaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                  for (NSString *recipientId in recipientIdsToLookup) {
                      if ([registeredRecipientIds containsObject:recipientId]) {
                          SignalRecipient *recipient =
                              [SignalRecipient markRecipientAsRegisteredAndGet:recipientId transaction:transaction];
                          [recipients addObject:recipient];
                      } else {
                          [SignalRecipient removeUnregisteredRecipient:recipientId transaction:transaction];
                      }
                  }
              }];

              success([recipients copy]);
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
