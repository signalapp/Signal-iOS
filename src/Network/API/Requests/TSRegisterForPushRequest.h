//
//  TSRegisterForPushRequest.h
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 10/13/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

@interface TSRegisterForPushRequest : TSRequest

- (id)initWithPushIdentifier:(NSString *)identifier voipIdentifier:(NSString *)voipId;

@end
