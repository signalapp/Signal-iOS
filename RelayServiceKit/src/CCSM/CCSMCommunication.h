//
//  CCSMCommunication.h
//  Forsta
//
//  Created by Greg Perkins on 5/31/17.
//  Copyright © 2017 Forsta. All rights reserved.
//

#ifndef CCSMCommunication_h
#define CCSMCommunication_h

@class SignalRecipient;

@interface CCSMCommManager : NSObject

+(void)refreshCCSMData;

+(void)requestLogin:(NSString *_Nonnull)userName
             orgName:(NSString *_Nonnull)orgName
            success:(void (^_Nullable)(void))successBlock
            failure:(void (^_Nullable)(NSError * _Nullable error))failureBlock ;

+(void)authenticateWithPayload:(NSDictionary *_Nonnull)payload
                    completion:(void (^_Nullable)(BOOL success, NSError * _Nullable error))completionBlock;

+(void)refreshSessionTokenAsynchronousSuccess:(void (^_Nullable)(void))successBlock
                                      failure:(void (^_Nullable)(NSError * _Nullable error))failureBlock;

+(void)requestPasswordResetForUser:(NSString *_Nonnull)userName
                               org:(NSString *_Nonnull)orgName
                        completion:(void (^_Nullable)(BOOL success, NSError * _Nullable error))completionBlock;

+(void)getThing:(NSString *_Nonnull)urlString
        success:(void (^_Nullable)(NSDictionary *_Nullable))successBlock
        failure:(void (^_Nullable)(NSError * _Nullable error))failureBlock;

+(void)checkAccountRegistrationWithCompletion:(void (^_Nullable)(NSDictionary * _Nullable response, NSError * _Nullable error))completionBlock;

+(void)registerDeviceWithParameters:(NSDictionary *_Nonnull)parameters
                         completion:(void (^_Nullable)(NSDictionary * _Nullable response, NSError * _Nullable error))completionBlock;

+(void)registerAccountWithParameters:(NSDictionary *_Nonnull)parameters
                          completion:(void (^_Nullable)(NSDictionary * _Nullable response, NSError * _Nullable error))completionBlock;

+(void)requestAccountCreationWithUserDict:(NSDictionary *_Nonnull)userDict
                                    token:(NSString *_Nonnull)token
                               completion:(void (^_Nullable)(BOOL success, NSError * _Nullable error))completionBlock;

+(void)requestPasswordAccountCreationWithFullName:(NSString *_Nonnull)fullName
                                         tagSlug:(NSString *_Nonnull)tagSlug
                                         password:(NSString *_Nonnull)password
                                            email:(NSString *_Nonnull)emailAddress
                                            phone:(NSString *_Nullable)phoneNumber
                                            token:(NSString *_Nonnull)token
                                       completion:(void (^_Nullable)(BOOL success, NSError * _Nullable error, NSDictionary *_Nullable payload))completionBlock;

+(void)sendDeviceProvisioningRequestWithPayload:(NSDictionary *_Nonnull)payload;

// Tag Math lookups
+(void)asyncTagLookupWithString:(NSString *_Nonnull)lookupString
                        success:(void (^_Nonnull)(NSDictionary *_Nonnull))successBlock
                        failure:(void (^_Nonnull)(NSError *_Nonnull))failureBlock;
@end

#endif /* CCSMCommunication_h */
