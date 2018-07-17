//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

//#import "SignalRecipient.h"

NS_ASSUME_NONNULL_BEGIN

//@class Contact;

@interface ContactDiscoveryService : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedService;

- (void)testService;

//- (nullable SignalRecipient *)synchronousLookup:(NSString *)identifier error:(NSError **)error;
//
//// This asynchronously tries to verify whether or not a contact id
//// corresponds to a service account.
////
//// The failure callback is invoked if the lookup fails _or_ if the
//// contact id doesn't correspond to an account.
//- (void)lookupIdentifier:(NSString *)identifier
//                 success:(void (^)(SignalRecipient *recipient))success
//                 failure:(void (^)(NSError *error))failure;
//
//// This asynchronously tries to verify whether or not a group of possible
//// contact ids correspond to service accounts.
////
//// The failure callback is only invoked if the lookup fails.  Otherwise,
//// the success callback is invoked with the (possibly empty) set of contacts
//// that were found.
//- (void)lookupIdentifiers:(NSArray<NSString *> *)identifiers
//                  success:(void (^)(NSArray<SignalRecipient *> *recipients))success
//                  failure:(void (^)(NSError *error))failure;
//
//- (void)updateSignalContactIntersectionWithABContacts:(NSArray<Contact *> *)abContacts
//                                              success:(void (^)(void))success
//                                              failure:(void (^)(NSError *error))failure;

@end

NS_ASSUME_NONNULL_END
