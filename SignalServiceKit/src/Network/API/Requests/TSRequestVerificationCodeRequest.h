//
//  TSRequestVerificationCodeRequest.h
//  Signal
//
//  Created by Frederic Jacobs on 02/12/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

@interface TSRequestVerificationCodeRequest : TSRequest

typedef enum { TSVerificationTransportVoice, TSVerificationTransportSMS } TSVerificationTransport;

- (TSRequest *)initWithPhoneNumber:(NSString *)phoneNumber transport:(TSVerificationTransport)transport;

@end
