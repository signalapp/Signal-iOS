// Copyright 2008 Cyrus Najmabadi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@class PBUnknownFieldSet_Builder;
@class PBUnknownFieldSet;
@class PBField;
@class PBCodedOutputStream;

@interface PBUnknownFieldSet : NSObject {
@private
  NSDictionary* fields;
}

@property (readonly, retain) NSDictionary* fields;

+ (PBUnknownFieldSet*) defaultInstance;

+ (PBUnknownFieldSet*) setWithFields:(NSMutableDictionary*) fields;
+ (PBUnknownFieldSet*) parseFromData:(NSData*) data;

+ (PBUnknownFieldSet_Builder*) builder;
+ (PBUnknownFieldSet_Builder*) builderWithUnknownFields:(PBUnknownFieldSet*) other;

- (void) writeAsMessageSetTo:(PBCodedOutputStream*) output;
- (void) writeToCodedOutputStream:(PBCodedOutputStream*) output;
- (NSData*) data;

- (int32_t) serializedSize;
- (int32_t) serializedSizeAsMessageSet;

- (BOOL) hasField:(int32_t) number;
- (PBField*) getField:(int32_t) number;

@end
