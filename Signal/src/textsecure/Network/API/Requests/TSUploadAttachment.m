//
//  TSUploadAttachment.m
//  TextSecureiOS
//
//  Created by Christine Corbett Moran on 12/3/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSUploadAttachment.h"
#import "TSAttachementStream.h"
#import <AFNetworking/AFHTTPRequestOperation.h>

@interface TSUploadAttachment ()
@property(nonatomic,strong) TSAttachement* attachment;
@end

@implementation TSUploadAttachment

-(TSRequest*) initWithAttachment:(TSAttachementStream*)attachment{
  
//  self = [super initWithURL:attachment.attachmentURL];
//  self.HTTPMethod = @"PUT";
//  self.attachment = attachment;
//    
//  [self setHTTPBody:[self.attachment getData]];
//  [self setAllHTTPHeaderFields: @{@"Content-Type": @"application/octet-stream"}];
//
//  return self;
  
}

@end
