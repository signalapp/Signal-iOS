//
//  TSSendSMSVerificationRequest.h
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 9/29/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "TSRequest.h"

@interface TSRequestVerificationCodeRequest : TSRequest

- (TSRequest*)initRequestForPhoneNumber:(NSString*)phoneNumber transport:(VerificationTransportType)transport;

@end
