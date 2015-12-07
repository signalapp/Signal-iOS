//
//  TSRedPhoneTokenRequest.m
//  Pods
//
//  Created by Frederic Jacobs on 20/12/15.
//
//

#import "TSConstants.h"
#import "TSRedPhoneTokenRequest.h"

@implementation TSRedPhoneTokenRequest

- (TSRequest *)init {
    self = [super initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/token/", textSecureAccountsAPI]]];

    self.HTTPMethod = @"GET";
    self.parameters = nil;

    return self;
}

@end
