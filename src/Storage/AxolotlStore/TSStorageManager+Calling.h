//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSStorageManager (Calling)

// phoneNumber is an e164 formatted phone number.
//
// callKitId is expected to have CallKitCallManager.kAnonymousCallHandlePrefix.
- (void)setPhoneNumber:(NSString *)phoneNumber forCallKitId:(NSString *)callKitId;

// returns an e164 formatted phone number or nil if no
// record can be found.
//
// callKitId is expected to have CallKitCallManager.kAnonymousCallHandlePrefix.
- (NSString *)phoneNumberForCallKitId:(NSString *)callKitId;

@end

NS_ASSUME_NONNULL_END
