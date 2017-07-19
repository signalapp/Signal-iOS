//
//  TSRequestAttachment.h
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 12/1/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

@interface TSAttachmentRequest : TSRequest

- (TSRequest *)initWithId:(UInt64)attachmentId relay:(NSString *)relay;

@end
