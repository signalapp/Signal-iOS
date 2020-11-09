//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalRecipient.h"

NS_ASSUME_NONNULL_BEGIN

@interface ContactsUpdater : NSObject

+ (instancetype)sharedUpdater;

// This asynchronously tries to verify whether or not a group of possible
// contact ids correspond to service accounts.
//
// The failure callback is only invoked if the lookup fails.  Otherwise,
// the success callback is invoked with the (possibly empty) set of contacts
// that were found.
- (void)lookupIdentifiers:(NSArray<NSString *> *)identifiers
                  success:(void (^)(NSArray<SignalRecipient *> *recipients))success
                  failure:(void (^)(NSError *error))failure;

@end

NS_ASSUME_NONNULL_END
