//
//  TSDeregisterAccountRequest.h
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 3/16/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

@interface TSDeregisterAccountRequest : TSRequest
- (id)initWithUser:(NSString*)user;
@end
