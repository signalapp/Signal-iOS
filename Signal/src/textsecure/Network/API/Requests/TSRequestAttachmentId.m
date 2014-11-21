//
//  TSRequestAttachmentId.m
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 12/1/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSConstants.h"
#import "TSRequestAttachmentId.h"

@implementation TSRequestAttachmentId
-(TSRequest*) init {
  
  self = [super initWithURL:[NSURL URLWithString:textSecureAttachmentsAPI]];
  self.HTTPMethod = @"GET";
  return self;
}

@end
