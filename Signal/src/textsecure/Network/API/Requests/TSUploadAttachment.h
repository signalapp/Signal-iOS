//
//  TSUploadAttachment.h
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 12/3/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"
#import "TSAttachementStream.h"

@interface TSUploadAttachment : TSRequest

-(TSRequest*) initWithAttachment:(TSAttachementStream*)attachment;

@end
