//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

@class SignedPreKeyRecord;
@class PreKeyRecord;

@interface TSRegisterSignedPrekeyRequest : TSRequest

- (id)initWithSignedPreKeyRecord:(SignedPreKeyRecord *)signedRecord;

@end
