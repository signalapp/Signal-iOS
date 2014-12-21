//
//  TSUploadAttachment.h
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 12/3/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"
#import "TSAttachmentStream.h"

@interface TSUploadAttachment : TSRequest

-(TSRequest*) initWithAttachment:(TSAttachmentStream*)attachment;

@end
