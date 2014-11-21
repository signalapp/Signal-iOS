//
//  TSRequestAttachment.m
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 12/1/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSRequestAttachment.h"
#import "Constants.h"
@implementation TSRequestAttachment
-(TSRequest*) initWithId:(NSNumber*) attachmentId {
  
  //self = [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@",textSecureAttachmentsAPI,attachmentId]]];
  self.HTTPMethod = @"GET";
  return self;
}


@end
