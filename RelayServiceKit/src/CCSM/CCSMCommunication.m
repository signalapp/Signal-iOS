//
//  CCSMCommunication.m
//  Forsta
//
//  Created by Greg Perkins on 5/31/17.
//  Copyright © 2017 Forsta. All rights reserved.
//

//#import "Environment.h"
#import "CCSMCommunication.h"
#import "CCSMStorage.h"
#import "TSAccountManager.h"
#import "SignalKeyingStorage.h"
#import "SecurityUtils.h"
#import "NSData+Base64.h"
#import "TSPreKeyManager.h"
#import "AFNetworking.h"
#import "FLDeviceRegistrationService.h"
#import <RelayServiceKit/RelayServiceKit-Swift.h>


#define FLTagMathPath @"/v1/directory/user/"

// TODO: Bring these in
//@import Fabric;
//@import Crashlytics;

@interface CCSMCommManager ()

@property (nullable, nonatomic, strong) NSString *userAwaitingVerification;
@property (nonatomic, strong) NSArray *controlTags;

@end

@implementation CCSMCommManager

+(void)requestLogin:(NSString *_Nonnull)userName
            orgName:(NSString *_Nonnull)orgName
            success:(void (^_Nullable)(void))successBlock
            failure:(void (^_Nullable)(NSError * _Nullable error))failureBlock
{
    NSString *lowerUsername = userName.lowercaseString;
    NSString *lowerOrgname = orgName.lowercaseString;
    
    NSString *urlString = [NSString stringWithFormat:@"%@/v1/login/send/%@/%@/?format=json", FLHomeURL, lowerOrgname, lowerUsername];
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:10];
    NSURLSession *sharedSession = NSURLSession.sharedSession;
    NSURLSessionDataTask *loginTask = [sharedSession dataTaskWithRequest:request
                                                       completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable connectionError)
                                       {
                                           NSHTTPURLResponse *HTTPresponse = (NSHTTPURLResponse *)response;
                                           DDLogDebug(@"Request Login - Server response code: %ld", (long)HTTPresponse.statusCode);
                                           DDLogDebug(@"%@",[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]);
                                           
                                           NSDictionary *result = nil;
                                           if (data) {  // Grab payload if its there
                                               result = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                                           }
                                           
                                           if (HTTPresponse.statusCode == 200) // SUCCESS!
                                           {
                                               [CCSMStorage.sharedInstance setOrgName:lowerOrgname];
                                               [CCSMStorage.sharedInstance setUserName:lowerUsername];
                                               DDLogDebug(@"login result's msg is: %@", [result objectForKey:@"msg"]);
                                               successBlock();
                                           }
                                           else  // Connection good, error from server
                                           {
                                               NSError *error = nil;
                                               if ([result objectForKey:@"non_field_errors"]) {
                                                   NSMutableString *errorDescription = [NSMutableString new];
                                                   for (NSString *message in [result objectForKey:@"non_field_errors"]) {
                                                       [errorDescription appendString:[NSString stringWithFormat:@"\n%@", message]];
                                                       
                                                       if ([message isEqualToString:@"password auth required"]) {
                                                           [CCSMStorage.sharedInstance setOrgName:lowerOrgname];
                                                           [CCSMStorage.sharedInstance setUserName:lowerUsername];
                                                           DDLogDebug(@"Password auth requested.");
                                                       }
                                                   }
                                                   error = [NSError errorWithDomain:NSURLErrorDomain
                                                                               code:HTTPresponse.statusCode
                                                                           userInfo:@{ NSLocalizedDescriptionKey : errorDescription }];
                                                   
                                               } else if ([result objectForKey:@"detail"]) {
                                                   error = [NSError errorWithDomain:NSURLErrorDomain
                                                                               code:HTTPresponse.statusCode
                                                                           userInfo:@{ NSLocalizedDescriptionKey : [result objectForKey:@"detail"] }];
                                               } else {
                                                   error = [NSError errorWithDomain:NSURLErrorDomain
                                                                               code:HTTPresponse.statusCode
                                                                           userInfo:@{NSLocalizedDescriptionKey:[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]}];
                                               }
                                               failureBlock(error);
                                           }
                                       }];
    
    [sharedSession flushWithCompletionHandler:^{
        [sharedSession resetWithCompletionHandler:^{
            [loginTask resume];
        }];
    }];
}

+(void)requestPasswordResetForUser:(NSString *)userName
                               org:(NSString *)orgName
                        completion:(void (^)(BOOL success, NSError *error))completionBlock
{
    NSString *lowerUsername = userName.lowercaseString;
    NSString *lowerOrgname = orgName.lowercaseString;

    // Make URL
    NSString *urlString = [NSString stringWithFormat:@"%@/v1/password/reset/", FLHomeURL];
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    
    // Make Request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    
    NSDictionary *payload = @{ @"fq_tag": [NSString stringWithFormat:@"@%@:%@", lowerUsername, lowerOrgname] };
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload
                                                       options:0
                                                         error:&error];
    if (error) {
        DDLogError(@"Auth payload conversion to data obejct failed for: %@", payload);
        completionBlock(NO, error);
        return;
    }
    [request setHTTPBody:jsonData];
    
    // Make session/session task
    NSURLSession *sharedSession = NSURLSession.sharedSession;
    NSURLSessionTask *validationTask = [sharedSession dataTaskWithRequest:request
                                                        completionHandler:^(NSData * _Nullable data,
                                                                            NSURLResponse * _Nullable response,
                                                                            NSError * _Nullable connectionError) {
                                                            NSHTTPURLResponse *HTTPresponse = (NSHTTPURLResponse *)response;
                                                            DDLogDebug(@"Verify Login - Server response code: %ld", (long)HTTPresponse.statusCode);
                                                            DDLogDebug(@"%@",[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]);
                                                            NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data
                                                                                                                   options:0
                                                                                                                     error:NULL];
                                                            if (connectionError != nil)  // Failed connection
                                                            {
                                                                completionBlock(NO, connectionError);
                                                            }
                                                            else if (HTTPresponse.statusCode == 200) // SUCCESS!
                                                            {
                                                                
                                                                completionBlock(YES, nil);
                                                            }
                                                            else  // Connection good, error from server
                                                            {
                                                                NSError *serverError = [NSError errorWithDomain:NSURLErrorDomain
                                                                                                           code:HTTPresponse.statusCode
                                                                                                       userInfo:@{NSLocalizedDescriptionKey:[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]}];
                                                                completionBlock(NO, serverError);
                                                            }
                                                        }];
    
    [sharedSession flushWithCompletionHandler:^{
        [sharedSession resetWithCompletionHandler:^{
            [validationTask resume];
        }];
    }];
}

+(void)authenticateWithPayload:(NSDictionary *)payload
                    completion:(void (^)(BOOL success, NSError *error))completionBlock
{
    // Make URL
    NSString *urlString = [NSString stringWithFormat:@"%@/v1/login/", FLHomeURL];
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];

    // Make Request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];

    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload
                                                       options:0
                                                         error:&error];
    if (error) {
        DDLogError(@"Auth payload conversion to data obejct failed for: %@", payload);
        completionBlock(NO, error);
        return;
    }
    [request setHTTPBody:jsonData];
    
    // Make session/session task
    NSURLSession *sharedSession = NSURLSession.sharedSession;
    NSURLSessionTask *validationTask = [sharedSession dataTaskWithRequest:request
                                                        completionHandler:^(NSData * _Nullable data,
                                                                            NSURLResponse * _Nullable response,
                                                                            NSError * _Nullable connectionError) {
                                                            NSHTTPURLResponse *HTTPresponse = (NSHTTPURLResponse *)response;
                                                            DDLogDebug(@"Verify Login - Server response code: %ld", (long)HTTPresponse.statusCode);
                                                            DDLogDebug(@"%@",[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]);
                                                            NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data
                                                                                                                   options:0
                                                                                                                     error:NULL];
                                                            if (connectionError != nil)  // Failed connection
                                                            {
                                                                completionBlock(NO, connectionError);
                                                            }
                                                            else if (HTTPresponse.statusCode == 200) // SUCCESS!
                                                            {
                                                                [self storeLocalUserDataWithPayload:result];
                                                                
                                                                completionBlock(YES, nil);
                                                            }
                                                            else  // Connection good, error from server
                                                            {
                                                                NSError *serverError = [NSError errorWithDomain:NSURLErrorDomain
                                                                                                     code:HTTPresponse.statusCode
                                                                                                 userInfo:@{NSLocalizedDescriptionKey:[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]}];
                                                                completionBlock(NO, serverError);
                                                            }
                                                        }];
    
    [sharedSession flushWithCompletionHandler:^{
        [sharedSession resetWithCompletionHandler:^{
            [validationTask resume];
        }];
    }];
    
}

+(void)refreshSessionTokenAsynchronousSuccess:(void (^_Nullable)(void))successBlock
                                      failure:(void (^_Nullable)(NSError * _Nullable error))failureBlock
{
    NSString *sessionToken = [CCSMStorage.sharedInstance getSessionToken];
    NSString *urlString = [NSString stringWithFormat:@"%@/v1/api-token-refresh/", FLHomeURL];
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    NSString *bodyString = [NSString stringWithFormat:@"token=%@", sessionToken];
    [request setHTTPBody:[bodyString dataUsingEncoding:NSUTF8StringEncoding]];
    
    [[NSURLSession.sharedSession dataTaskWithRequest:request
                                   completionHandler:^(NSData * _Nullable data,
                                                       NSURLResponse * _Nullable response,
                                                       NSError * _Nullable connectionError) {
                                       NSHTTPURLResponse *HTTPresponse = (NSHTTPURLResponse *)response;
                                       DDLogDebug(@"Refresh Session Token - Server response code: %ld", (long)HTTPresponse.statusCode);
                                       DDLogDebug(@"%@",[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]);
                                       
                                       NSDictionary *result = nil;
                                       if (data) {
                                           result = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                                       }
                                       
                                       if (connectionError != nil)  // Failed connection
                                       {
                                           failureBlock(connectionError);
                                       }
                                       else if (HTTPresponse.statusCode == 200) // SUCCESS!
                                       {
                                           [self storeLocalUserDataWithPayload:result];
                                           
                                           successBlock();
                                       }
                                       else  // Connection good, error from server
                                       {
                                           NSMutableString *errorMessage = [NSMutableString new];
                                           if (result) {
                                               NSArray *errorMessages = [result objectForKey:@"non_field_errors"];
                                               for (NSString *message in errorMessages) {
                                                   [errorMessage appendString:[NSString stringWithFormat:@"\n%@", message]];
                                               }
                                           }
                                           
                                           NSError *error = nil;
                                           if (errorMessage.length == 0) {
                                               error = [NSError errorWithDomain:NSURLErrorDomain
                                                                           code:HTTPresponse.statusCode
                                                                       userInfo:@{ NSLocalizedDescriptionKey : [NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode] }];
                                           } else {
                                               error = [NSError errorWithDomain:NSURLErrorDomain
                                                                           code:HTTPresponse.statusCode
                                                                       userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
                                           }
                                           
                                           failureBlock(error);
                                       }
                                       
                                   }] resume];
}

+(void)updateAllTheThings:(NSString *)urlString
               collection:(NSMutableDictionary *)collection
                  success:(void (^)(void))successBlock
                  failure:(void (^)(NSError *error))failureBlock
{
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    [self getPage:url
          success:^(NSDictionary *result){
              NSArray *results = [result objectForKey:@"results"];
              for (id thing in results) {
                  [collection setValue:thing forKey:[thing valueForKey:@"id"]];
              }
              NSString *next = [result valueForKey:@"next"];
              if (next && (NSNull *)next != [NSNull null]) {
                  [self updateAllTheThings:next
                                collection:collection
                                   success:successBlock
                                   failure:failureBlock];
              } else {
                  successBlock();
              }
          }
          failure:^(NSError *err){
              failureBlock(err);
          }];
}

+(void)getPage:(NSURL *)url
       success:(void (^)(NSDictionary *result))successBlock
       failure:(void (^)(NSError *error))failureBlock
{
    NSMutableURLRequest *request = [self authRequestWithURL:url];
    [request setHTTPMethod:@"GET"];
    
    [[NSURLSession.sharedSession dataTaskWithRequest:request
                                   completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable connectionError) {
                                       
                                       if (data.length > 0 && connectionError == nil)
                                       {
                                           NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data
                                                                                                  options:0
                                                                                                    error:NULL];
                                           successBlock(result);
                                       }
                                       else if (connectionError != nil) {
                                           failureBlock(connectionError);
                                       }
                                   }] resume];
}


+(void)getThing:(NSString *)urlString
        success:(void (^)(NSDictionary *))successBlock
        failure:(void (^)(NSError *error))failureBlock;
{
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:config];
    
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    NSMutableURLRequest *request = [self authRequestWithURL:url];
    [request setHTTPMethod:@"GET"];
    
    NSURLSessionDataTask *task = [manager dataTaskWithRequest:request
                                               uploadProgress:nil
                                             downloadProgress:nil
                                            completionHandler:^(NSURLResponse * _Nonnull response, id _Nullable responseObject, NSError * _Nullable connectionError) {
                                                if (connectionError == nil) {
                                                    NSDictionary *result = nil;
                                                    if ([responseObject isKindOfClass:[NSDictionary class]]) {
                                                        result = responseObject;
                                                    }
                                                    successBlock(result);
                                                } else {
                                                    failureBlock(connectionError);
                                                }

                                            }];
    [task resume];
}

#pragma mark - Refresh methods
+(void)storeLocalUserDataWithPayload:(NSDictionary *)payload
{
    // TODO: Move this to the account manager
    if (payload) {
        NSDictionary *userDict = [payload objectForKey:@"user"];
        NSString *userID = [userDict objectForKey:@"id"];
        TSAccountManager.sharedInstance.phoneNumberAwaitingVerification = userID;
        // Check to see if user changed.  If so, wiped the database.
        if ([TSAccountManager localUID].length > 0 &&
            ![[TSAccountManager localUID] isEqualToString:userID]) {
            // FIXME: Skipping this until later
//            [SignalApp resetAppData];
            [CCSMStorage.sharedInstance setUsers:@{ }];
            [CCSMStorage.sharedInstance setOrgInfo:@{ }];
            [CCSMStorage.sharedInstance setTags:@{ }];
        }
        
        [TSAccountManager.sharedInstance didRegister];
        
        [CCSMStorage.sharedInstance setSessionToken:[payload objectForKey:@"token"]];
        
        [CCSMStorage.sharedInstance setUserInfo:userDict];
        [RelayRecipient getOrCreateRecipientWithUserDictionary:userDict];
        
        NSDictionary *orgDict = [userDict objectForKey:@"org"];
        [CCSMStorage.sharedInstance setOrgInfo:orgDict];
        
        NSString *orgUrl = [orgDict objectForKey:@"url"];
        [self processOrgInfoWithURL:orgUrl];
    }
}

+(void)refreshCCSMData
{
    [self refreshCCSMUsers];
    [self refreshCCSMTags];
}

+(void)refreshCCSMUsers
{
    
    NSMutableDictionary *users = [NSMutableDictionary new];
    
    [self updateAllTheThings:[NSString stringWithFormat:@"%@/v1/user/", FLHomeURL]
                  collection:users
                     success:^{
                         DDLogDebug(@"Refreshed all users.");
                         [CCSMStorage.sharedInstance setUsers:[NSDictionary dictionaryWithDictionary:users]];
                         [self notifyOfUsersRefresh];
                     }
                     failure:^(NSError *err){
                         DDLogError(@"Failed to refresh all users. Error: %@", err.localizedDescription);
                     }];
}

+(void)refreshCCSMTags
{
    NSMutableDictionary *tags = [NSMutableDictionary new];
    
    [self updateAllTheThings:[NSString stringWithFormat:@"%@/v1/tag/", FLHomeURL]
                  collection:tags
                     success:^{
                         NSMutableDictionary *holdingDict = [NSMutableDictionary new];
                         for (NSString *key in [tags allKeys]) {
                             NSDictionary *dict = [tags objectForKey:key];
                             if (![self.controlTags containsObject:[dict objectForKey:@"slug"]]) {
                                 [holdingDict setObject:dict forKey:key];
                             }
                         }
                         [CCSMStorage.sharedInstance setTags:[NSDictionary dictionaryWithDictionary:holdingDict]];
                         [self notifyOfTagsRefresh];
                         DDLogDebug(@"Refreshed all tags.");
                     }
                     failure:^(NSError *err){
                         DDLogError(@"Failed to refresh all tags. Error: %@", err.localizedDescription);
                     }];
}

+(void)processOrgInfoWithURL:(NSString *)urlString
{
    if (urlString.length > 0) {
        [self getThing:urlString
               success:^(NSDictionary *org){
                   DDLogDebug(@"Retrieved org info after login validation");
                   [CCSMStorage.sharedInstance setOrgInfo:org];
                   // Extract and save org prefs
                   NSDictionary *prefsDict = [org objectForKey:@"preferences"];
                   if (prefsDict) {
                       // Currently no prefs to process
                       DDLogDebug(@"Successfully processed Org preferences.");
                   }
               }
               failure:^(NSError *err){
                   DDLogDebug(@"Failed to retrieve org info after login validation. Error: %@", err.description);
               }];
    }
}

+(void)notifyOfUsersRefresh
{
    [[NSNotificationCenter defaultCenter] postNotificationName:FLCCSMUsersUpdated object:nil];
}

+(void)notifyOfTagsRefresh
{
    [[NSNotificationCenter defaultCenter] postNotificationName:FLCCSMTagsUpdated object:nil];
}

#pragma mark - CCSM proxied TextSecure registration
+(void)registerDeviceWithParameters:(NSDictionary *)parameters
                         completion:(void (^)(NSDictionary *response, NSError *error))completionBlock
{
    NSString *TSSUrlString = [[CCSMStorage new] textSecureURL];
    NSString *urlString = [NSString stringWithFormat:@"%@/v1/devices%@", TSSUrlString, [parameters objectForKey:@"urlParms"]];
    
    NSString *rawToken = [NSString stringWithFormat:@"%@:%@", [parameters objectForKey:@"username"], [parameters objectForKey:@"password"]];
    NSData *rawData = [rawToken dataUsingEncoding:kCFStringEncodingUTF8];
    NSString *base64String = [rawData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
    NSString *authHeader = [@"Basic " stringByAppendingString:base64String];

    
//    NSString *authHeader = [HttpRequest computeBasicAuthorizationTokenForLocalNumber:[parameters objectForKey:@"username"]
//                                                                         andPassword:[parameters objectForKey:@"password"]];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = @"PUT";
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [request addValue:authHeader forHTTPHeaderField:@"Authorization"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:[parameters objectForKey:@"jsonBody"] options:0 error:nil];
    
    [[NSURLSession.sharedSession dataTaskWithRequest:request
                                   completionHandler:^(NSData * _Nullable data,
                                                       NSURLResponse * _Nullable response,
                                                       NSError * _Nullable connectionError) {
                                       NSHTTPURLResponse *HTTPresponse = (NSHTTPURLResponse *)response;
                                       DDLogDebug(@"Register device with TSS - Server response code: %ld", (long)HTTPresponse.statusCode);
                                       DDLogDebug(@"%@",[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]);
                                       NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data
                                                                                              options:0
                                                                                                error:NULL];
                                       
                                       if (connectionError != nil)  // Failed connection
                                       {
                                           completionBlock(result, connectionError);
                                       }
                                       else if (HTTPresponse.statusCode == 200) // SUCCESS!
                                       {
                                           if (data.length > 0 && connectionError == nil)
                                           {
                                               completionBlock(result, nil);
                                           }
                                       }
                                       else  // Connection good, error from server
                                       {
                                           NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                                                                code:HTTPresponse.statusCode
                                                                            userInfo:@{NSLocalizedDescriptionKey:[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]}];
                                           completionBlock(result, error);
                                       }
                                   }] resume];
}

+(void)checkAccountRegistrationWithCompletion:(void (^)(NSDictionary *response, NSError *error))completionBlock
{
    // Check for other devices...
    NSString *tmpurlString = [NSString stringWithFormat:@"%@/v1/provision/account", FLHomeURL];
    [self getThing:tmpurlString
           success:^(NSDictionary *payload)
     {
         NSString *serverURL = [payload objectForKey:@"serverUrl"];
         NSString *userId = [payload objectForKey:@"userId"];
         if (![TSAccountManager.sharedInstance.localUID isEqualToString:userId]) {
             DDLogError(@"SECURITY VIOLATION! USERID MISMATCH! IDs: %@, %@", userId, [TSAccountManager.sharedInstance localUID]);
             // TODO: Make a better error
             NSError *err = [NSError new];
             completionBlock(payload, err);
         }
         if (serverURL.length == 0) {
             DDLogError(@"TSS Server address not provided!");
             // TODO: Make a better error
             NSError *err = [NSError new];
             completionBlock(payload, err);
         }
         completionBlock(payload, nil);
     } failure:^(NSError *error) {
         completionBlock(nil, error);
     }];
}

+(void)registerAccountWithParameters:(NSDictionary *)parameters
                      completion:(void (^)(NSDictionary *response, NSError *error))completionBlock
{
    NSString *urlString = [NSString stringWithFormat:@"%@/v1/provision-proxy/", FLHomeURL];
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    NSMutableURLRequest *request = [self authRequestWithURL:url];
    [request setHTTPMethod:@"PUT"];
    
    NSDictionary *payload = [parameters objectForKey:@"jsonBody"];
    if (!payload) {
        DDLogError(@"Invalid parameters in for TSS account registration.");
        // TODO: Make better error
        NSError *err = [NSError new];
        completionBlock(nil, err);
        return;
    }
    
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    [request setHTTPBody:bodyData];
    
    [[NSURLSession.sharedSession dataTaskWithRequest:request
                                   completionHandler:^(NSData * _Nullable data,
                                                       NSURLResponse * _Nullable response,
                                                       NSError * _Nullable connectionError) {
                                       NSHTTPURLResponse *HTTPresponse = (NSHTTPURLResponse *)response;
                                       DDLogDebug(@"Register with TSS - Server response code: %ld", (long)HTTPresponse.statusCode);
                                       DDLogDebug(@"%@",[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]);
                                       NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data
                                                                                              options:0
                                                                                                error:NULL];
                                       if (connectionError != nil)  // Failed connection
                                       {
                                           completionBlock(result, connectionError);
                                       }
                                       else if (HTTPresponse.statusCode == 200) // SUCCESS!
                                       {
                                           if (data.length > 0 && connectionError == nil)
                                           {
                                               completionBlock(result, nil);
                                           }
                                       }
                                       else  // Connection good, error from server
                                       {
                                           NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                                                                code:HTTPresponse.statusCode
                                                                            userInfo:@{NSLocalizedDescriptionKey:[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]}];
                                           completionBlock(result, error);
                                       }
                                   }] resume];
}

#pragma mark - Device provisioning
+(void)sendDeviceProvisioningRequestWithPayload:(NSDictionary *_Nonnull)payload
{
    NSString *uuid = [payload objectForKey:@"uuid"];
    NSString *key = [payload objectForKey:@"key"];
    
    if (uuid.length == 0 || key.length == 0) {
        DDLogError(@"Attempt to send provisioning request with malformed payload.");
        return;
    }
    
    NSString *urlString = [NSString stringWithFormat:@"%@/v1/provision/request", FLHomeURL];
    NSMutableURLRequest *request = [self authRequestWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = @"POST";
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    request.HTTPBody = bodyData;
    
    [[NSURLSession.sharedSession dataTaskWithRequest:request
                                   completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                                       NSHTTPURLResponse *HTTPresponse = (NSHTTPURLResponse *)response;
                                       DDLogDebug(@"Device Provision Request - Server response code: %ld", (long)HTTPresponse.statusCode);
                                       DDLogDebug(@"%@",[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]);
                                       if (error != nil)  // Failed connection
                                       {
                                           DDLogError(@"Device Provision Request failed with error: %@", error.localizedDescription);
                                       }
                                       else if (HTTPresponse.statusCode >= 200 && HTTPresponse.statusCode <= 204) // SUCCESS!
                                       {
                                           NSDictionary *result = nil;
                                           if (data.length > 0 && error == nil)
                                           {
                                               result = [NSJSONSerialization JSONObjectWithData:data
                                                                                        options:0
                                                                                          error:NULL];
                                           }
                                           DDLogInfo(@"Device Provision Request sucessully sent.  Response: %@", result);
                                       }
                                       else  // Connection good, error from server
                                       {
                                           NSError *rejectError = [NSError errorWithDomain:NSURLErrorDomain
                                                                                      code:HTTPresponse.statusCode
                                                                                  userInfo:@{NSLocalizedDescriptionKey:[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]}];
                                           DDLogError(@"Device Provision Request rejected with error: %@", rejectError);
                                       }
                                   }] resume];
}

//#pragma mark - User/recipient Lookup methods
//+(SignalRecipient *)recipientFromCCSMWithID:(NSString *)userId
//{
//    __block SignalRecipient *recipient = nil;
//
//    [TSStorageManager.sharedManager.writeDbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction * _Nonnull transaction) {
//        recipient = [self recipientFromCCSMWithID:userId transaction:transaction];
//    }];
//
//    return recipient;
//}
//
//+(SignalRecipient *)recipientFromCCSMWithID:(NSString *)userId transaction:(YapDatabaseReadWriteTransaction *)transaction
//{
//    NSAssert(![NSThread isMainThread], @"Must NOT access recipientFromCCSMWithID on main thread!");
//    __block SignalRecipient *recipient = nil;
//
//    if (userId) {
//        __block dispatch_semaphore_t sema = dispatch_semaphore_create(0);
//
//        NSString *url = [NSString stringWithFormat:@"%@/v1/directory/user/?id=%@", FLHomeURL, userId];
//        [self getThing:url
//               success:^(NSDictionary *payload) {
//                   if (((NSNumber *)[payload objectForKey:@"count"]).integerValue > 0) {
//                       NSArray *tmpArray = [payload objectForKey:@"results"];
//                       NSDictionary *results = [tmpArray lastObject];
//                       recipient = [SignalRecipient getOrCreateRecipientWithUserDictionary:results transaction:transaction];
//                       dispatch_semaphore_signal(sema);
//                   }
//               }
//               failure:^(NSError *error) {
//                   DDLogDebug(@"CCSM User lookup failed or returned no results.");
//                   dispatch_semaphore_signal(sema);
//               }];
//
//        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
//    }
//    return recipient;
//}

#pragma mark - Public account creation
+(void)requestPasswordAccountCreationWithFullName:(NSString *_Nonnull)fullName
                                         tagSlug:(NSString *_Nonnull)tagSlug
                                         password:(NSString *_Nonnull)password
                                            email:(NSString *_Nonnull)emailAddress
                                            phone:(NSString *_Nullable)phoneNumber
                                            token:(NSString *_Nonnull)token
                                       completion:(void (^_Nullable)(BOOL success, NSError * _Nullable error, NSDictionary *_Nullable payload))completionBlock
{
    // Build the payload
    NSString *lowerTagslug = tagSlug.lowercaseString;
    
    NSDictionary *payload = @{ @"fullname" : fullName,
                               @"tag_slug" :lowerTagslug,
                               @"email" : emailAddress,
                               @"password" : password,
                               @"captcha" : token
                               };
    if (phoneNumber.length > 0) {
        NSMutableDictionary *tmp = [payload mutableCopy];
        [tmp setObject:phoneNumber forKey:@"phone"];
        payload = [NSDictionary dictionaryWithDictionary:tmp];
    }

    // URL...
    NSString *urlString = [NSString stringWithFormat:@"%@/v1/join/", FLHomeURL];
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];

    // Build request...
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"https://app.forsta.io/join" forHTTPHeaderField:@"Referer"];
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    [request setHTTPBody:bodyData];
    
    // Do the deed...
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:config];

    [[manager dataTaskWithRequest:request
                  uploadProgress:nil
                downloadProgress:nil
                completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable connectionError) {
                    NSHTTPURLResponse *HTTPresponse = (NSHTTPURLResponse *)response;
                    DDLogDebug(@"Request Account Creation - Server response code: %ld", (long)HTTPresponse.statusCode);
                    DDLogDebug(@"%@",[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]);

                    NSDictionary *result = nil;
                    if ([responseObject isKindOfClass:[NSDictionary class]]) {
                        result = responseObject;
                    }

                    if (connectionError != nil) {
                        completionBlock(NO, connectionError, result);
                    } else if (HTTPresponse.statusCode >= 200 && HTTPresponse.statusCode <= 204) { // SUCCESS!
                        
                        NSString *userSlug = [result objectForKey:@"nametag"];
                        NSString *orgSlug = [result objectForKey:@"orgslug"];
                        NSString *sessionToken = [result objectForKey:@"jwt"];
                        [CCSMStorage.sharedInstance setOrgName:orgSlug];
                        [CCSMStorage.sharedInstance setUserName:userSlug];
                        [CCSMStorage.sharedInstance setSessionToken:sessionToken];
                        
                        completionBlock(YES, nil, result);
                    } else { // Connection good, error from server 
                        NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                                             code:HTTPresponse.statusCode
                                                         userInfo:@{NSLocalizedDescriptionKey:[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]}];
                        completionBlock(false, error, result);
                    }
                    

                }] resume];
}

+(void)requestAccountCreationWithUserDict:(NSDictionary *)userDict
                                    token:(NSString *)token
                               completion:(void (^)(BOOL success, NSError *error))completionBlock
{
    NSString *firstName = [userDict objectForKey:@"first_name"];
    NSString *lastName = [userDict objectForKey:@"last_name"];
    NSString *phone = [userDict objectForKey:@"phone"];
    NSString *email = [userDict objectForKey:@"email"];

    if (firstName.length == 0 ||
        lastName.length == 0 ||
        phone.length == 0 ||
        email.length == 0)
    {
        // Bad payload, bounce
        NSError *error = [NSError errorWithDomain:@"CCSM.Invalid.input" code:9001 userInfo:nil];
        completionBlock(false, error);
    } else {
        
        // Build the v1/join payload
        NSString *username = [NSString stringWithFormat:@"%@.%@", firstName.lowercaseString, lastName.lowercaseString];
        NSString *fullname = [NSString stringWithFormat:@"%@ %@", firstName, lastName];
        
        NSDictionary *payload = @{ @"username": username,
                                   @"fullname": fullname,
                                   @"phone": phone,
                                   @"email": email,
                                   @"captcha": token
                                   };
        
        
        NSString *urlString = [NSString stringWithFormat:@"%@/v1/join/", FLHomeURL];
        NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        [request setHTTPMethod:@"POST"];
        [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
        [request setValue:@"https://app.forsta.io/join" forHTTPHeaderField:@"Referer"];
        
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
        [request setHTTPBody:bodyData];
        
        [[NSURLSession.sharedSession dataTaskWithRequest:request
                                       completionHandler:^(NSData * _Nullable data,
                                                           NSURLResponse * _Nullable response,
                                                           NSError * _Nullable connectionError) {
                                           NSHTTPURLResponse *HTTPresponse = (NSHTTPURLResponse *)response;
                                           DDLogDebug(@"Request Account Creation - Server response code: %ld", (long)HTTPresponse.statusCode);
                                           DDLogDebug(@"%@",[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]);
                                           
                                           NSDictionary *result = nil;
                                           if (data.length > 0) {
                                               result = [NSJSONSerialization JSONObjectWithData:data
                                                                                        options:0
                                                                                          error:NULL];
                                           }
                                           
                                           if (connectionError != nil)  // Failed connection
                                           {
                                               completionBlock(false, connectionError);
                                           }
                                           else if (HTTPresponse.statusCode >= 200 && HTTPresponse.statusCode <= 204) // SUCCESS!
                                           {
                                               if (data.length > 0 && connectionError == nil)
                                               {
                                                   CCSMStorage *ccsmStore = [CCSMStorage new];
                                                   NSString *userSlug = [result objectForKey:@"nametag"];
                                                   NSString *orgSlug = [result objectForKey:@"orgslug"];
                                                   [ccsmStore setOrgName:orgSlug];
                                                   [ccsmStore setUserName:userSlug];
                                               }
                                               completionBlock(true, nil);
                                           }
                                           else if (HTTPresponse.statusCode == 400 && [result objectForKey:@"username"]) {
                                               
                                               NSMutableString *errorString = [NSLocalizedString(@"REGISTER_USERNAME_ERROR", nil) mutableCopy];
                                               NSArray *array = (NSArray *)[result objectForKey:@"username"];
                                               [errorString appendString:[array lastObject]];
                                               
                                               NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                                                                    code:HTTPresponse.statusCode
                                                                                userInfo:@{ NSLocalizedDescriptionKey: errorString }];
                                               completionBlock(false, error);
                                           }
                                           else  // Connection good, error from server
                                           {
                                               NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                                                                    code:HTTPresponse.statusCode
                                                                                userInfo:@{NSLocalizedDescriptionKey:[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]}];
                                               completionBlock(false, error);
                                           }
                                       }] resume];
    }
}

// MARK: - Tag Math lookup
+(void)asyncTagLookupWithString:(NSString *_Nonnull)lookupString
                        success:(void (^_Nonnull)(NSDictionary *_Nonnull))successBlock
                        failure:(void (^_Nonnull)(NSError *_Nonnull))failureBlock;
{
    NSMutableURLRequest *request = [self tagMathRequestForString:lookupString];
    
    [[NSURLSession.sharedSession dataTaskWithRequest:request
                                   completionHandler:^(NSData * _Nullable data,
                                                       NSURLResponse * _Nullable response,
                                                       NSError * _Nullable connectionError) {
                                       NSHTTPURLResponse *HTTPresponse = (NSHTTPURLResponse *)response;
                                       DDLogDebug(@"TagMath Lookup async - Server response code: %ld", (long)HTTPresponse.statusCode);
                                       DDLogDebug(@"%@",[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]);
                                       
                                       if (connectionError != nil)  // Failed connection
                                       {
                                           DDLogDebug(@"Tag Math.  Error: %@", connectionError);
                                           failureBlock(connectionError);
                                       }
                                       else if (HTTPresponse.statusCode == 200) // SUCCESS!
                                       {
                                           NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data
                                                                                                  options:0
                                                                                                    error:NULL];
                                           successBlock(result);
                                       }
                                       else  // Connection good, error from server
                                       {
                                           NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                                                                code:HTTPresponse.statusCode
                                                                            userInfo:@{NSLocalizedDescriptionKey:[NSHTTPURLResponse localizedStringForStatusCode:HTTPresponse.statusCode]}];
                                           failureBlock(error);
                                       }
                                   }] resume];
}

+(NSMutableURLRequest *)tagMathRequestForString:(NSString *)lookupString
{
    NSString *homeURL = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CCSM_Home_URL"];
    NSString *urlString = [NSString stringWithFormat:@"%@%@?expression=%@", homeURL, FLTagMathPath, lookupString];
    NSURL *url = [NSURL URLWithString:[urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    NSMutableURLRequest *request = [self authRequestWithURL:url];
    [request setHTTPMethod:@"GET"];
    
    return request;
}

// MARK: - Helper
+(NSMutableURLRequest *)authRequestWithURL:(NSURL *)url
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    NSString *sessionToken = [CCSMStorage.sharedInstance getSessionToken];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [request addValue:[NSString stringWithFormat:@"JWT %@", sessionToken] forHTTPHeaderField:@"Authorization"];
    
    return request;
}

#pragma mark - Accessors
+(NSArray *)controlTags
{
    return @[ @".", @"role", @"position" ];
}

@end
