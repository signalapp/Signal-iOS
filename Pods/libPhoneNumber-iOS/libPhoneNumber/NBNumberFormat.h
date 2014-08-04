//
//  NBPhoneNumberFormat.h
//  libPhoneNumber
//
//

#import <Foundation/Foundation.h>

@interface NBNumberFormat : NSObject

// from phonemetadata.pb.js
/* 1 */ @property (nonatomic, strong, readwrite) NSString *pattern;
/* 2 */ @property (nonatomic, strong, readwrite) NSString *format;
/* 3 */ @property (nonatomic, strong, readwrite) NSMutableArray *leadingDigitsPatterns;
/* 4 */ @property (nonatomic, strong, readwrite) NSString *nationalPrefixFormattingRule;
/* 6 */ @property (nonatomic, assign, readwrite) BOOL nationalPrefixOptionalWhenFormatting;
/* 5 */ @property (nonatomic, strong, readwrite) NSString *domesticCarrierCodeFormattingRule;

- (id)initWithData:(id)data;

@end
