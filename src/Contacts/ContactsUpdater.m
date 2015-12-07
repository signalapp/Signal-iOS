//
//  ContactsManager+updater.m
//  Signal
//
//  Created by Frederic Jacobs on 21/11/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.
//

#import "ContactsUpdater.h"

#import "Contact.h"
#import "Cryptography.h"
#import "PhoneNumber.h"
#import "TSContactsIntersectionRequest.h"
#import "TSNetworkManager.h"
#import "TSStorageManager.h"

@implementation ContactsUpdater

+ (instancetype)sharedUpdater {
    static dispatch_once_t onceToken;
    static id sharedInstance = nil;
    dispatch_once(&onceToken, ^{
      sharedInstance = [self.class new];
    });
    return sharedInstance;
}

- (void)synchronousLookup:(NSString *)identifier
                  success:(void (^)(SignalRecipient *))success
                  failure:(void (^)(NSError *error))failure {
    __block dispatch_semaphore_t sema  = dispatch_semaphore_create(0);
    __block SignalRecipient *recipient = nil;
    __block NSError *error             = nil;

    [self lookupIdentifier:identifier
        success:^(NSSet<NSString *> *matchedIds) {
          if ([matchedIds count] == 1) {
              [[TSStorageManager sharedManager]
                      .dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
                recipient = [SignalRecipient recipientWithTextSecureIdentifier:identifier withTransaction:transaction];
              }];
          } else {
              error = [NSError errorWithDomain:@"contactsmanager.notfound" code:NOTFOUND_ERROR userInfo:nil];
          }
          dispatch_semaphore_signal(sema);
        }
        failure:^(NSError *blockerror) {
          error = blockerror;
          dispatch_semaphore_signal(sema);
        }];

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    if (error) {
        SYNC_BLOCK_SAFE_RUN(failure, error);
    } else {
        SYNC_BLOCK_SAFE_RUN(success, recipient);
    }

    return;
}


- (void)lookupIdentifier:(NSString *)identifier
                 success:(void (^)(NSSet<NSString *> *matchedIds))success
                 failure:(void (^)(NSError *error))failure {
    [self contactIntersectionWithSet:[NSSet setWithObject:identifier]
        success:^(NSSet<NSString *> *matchedIds) {
          BLOCK_SAFE_RUN(success, matchedIds);
        }
        failure:^(NSError *error) {
          BLOCK_SAFE_RUN(failure, error);
        }];
}

- (void)updateSignalContactIntersectionWithABContacts:(NSArray<Contact *> *)abContacts
                                              success:(void (^)())success
                                              failure:(void (^)(NSError *error))failure {
    NSMutableSet<NSString *> *abPhoneNumbers = [NSMutableSet set];

    for (Contact *contact in abContacts) {
        for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
            [abPhoneNumbers addObject:phoneNumber.toE164];
        }
    }

    __block NSMutableSet *recipientIds = [NSMutableSet set];
    [[TSStorageManager sharedManager]
            .dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
      NSArray *allRecipientKeys = [transaction allKeysInCollection:[SignalRecipient collection]];
      [recipientIds addObjectsFromArray:allRecipientKeys];
    }];

    NSMutableSet<NSString *> *allContacts = [[abPhoneNumbers setByAddingObjectsFromSet:recipientIds] mutableCopy];

    [self contactIntersectionWithSet:allContacts
        success:^(NSSet<NSString *> *matchedIds) {
          [recipientIds minusSet:matchedIds];

          // Cleaning up unregistered identifiers
          [[TSStorageManager sharedManager]
                  .dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            for (NSString *identifier in recipientIds) {
                SignalRecipient *recipient =
                    [SignalRecipient fetchObjectWithUniqueID:identifier transaction:transaction];
                [recipient removeWithTransaction:transaction];
            }
          }];

          BLOCK_SAFE_RUN(success);
        }
        failure:^(NSError *error) {
          BLOCK_SAFE_RUN(failure, error);
        }];
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

      TSRequest *request = [[TSContactsIntersectionRequest alloc] initWithHashesArray:hashes];
      [[TSNetworkManager sharedManager] makeRequest:request
          success:^(NSURLSessionDataTask *tsTask, id responseDict) {
            NSMutableDictionary *attributesForIdentifier = [NSMutableDictionary dictionary];
            NSArray *contactsArray                       = [(NSDictionary *)responseDict objectForKey:@"contacts"];

            // Map attributes to phone numbers
            if (contactsArray) {
                for (NSDictionary *dict in contactsArray) {
                    NSString *hash       = [dict objectForKey:@"token"];
                    NSString *identifier = [phoneNumbersByHashes objectForKey:hash];

                    if (!identifier) {
                        DDLogWarn(@"An interesecting hash wasn't found in the mapping.");
                        break;
                    }

                    [attributesForIdentifier setObject:dict forKey:identifier];
                }
            }

            // Insert or update contact attributes
            [[TSStorageManager sharedManager]
                    .dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
              for (NSString *identifier in attributesForIdentifier) {
                  SignalRecipient *recipient =
                      [SignalRecipient recipientWithTextSecureIdentifier:identifier withTransaction:transaction];
                  if (!recipient) {
                      recipient =
                          [[SignalRecipient alloc] initWithTextSecureIdentifier:identifier relay:nil supportsVoice:NO];
                  }

                  NSDictionary *attributes = [attributesForIdentifier objectForKey:identifier];

                  NSString *relay = [attributes objectForKey:@"relay"];
                  if (relay) {
                      recipient.relay = relay;
                  } else {
                      recipient.relay = nil;
                  }

                  BOOL supportsVoice = [[attributes objectForKey:@"voice"] boolValue];
                  if (supportsVoice) {
                      recipient.supportsVoice = YES;
                  } else {
                      recipient.supportsVoice = NO;
                  }

                  [recipient saveWithTransaction:transaction];
              }
            }];

            BLOCK_SAFE_RUN(success, [NSSet setWithArray:attributesForIdentifier.allKeys]);
          }
          failure:^(NSURLSessionDataTask *task, NSError *error) {
            BLOCK_SAFE_RUN(failure, error);
          }];
    });
}

@end
