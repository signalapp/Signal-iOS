//
//  TSSubmitMessageRequest.h
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 11/30/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "TSRequest.h"

@interface TSSubmitMessageRequest : TSRequest

- (TSRequest *)initWithRecipient:(NSString *)contactRegisteredID
                        messages:(NSArray *)messages
                           relay:(NSString *)relay
                       timeStamp:(uint64_t)timeStamp;

@end
