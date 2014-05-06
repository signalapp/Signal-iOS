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

@class PBField;
@class PBMutableField;
@class PBUnknownFieldSet;
@class PBUnknownFieldSet_Builder;
@class PBCodedInputStream;

@interface PBUnknownFieldSet_Builder : NSObject {
@private
  NSMutableDictionary* fields;

  // Optimization:  We keep around a builder for the last field that was
  //   modified so that we can efficiently add to it multiple times in a
  //   row (important when parsing an unknown repeated field).
  int32_t lastFieldNumber;

  PBMutableField* lastField;
}

+ (PBUnknownFieldSet_Builder*) newBuilder:(PBUnknownFieldSet*) unknownFields;

- (PBUnknownFieldSet*) build;
- (PBUnknownFieldSet_Builder*) mergeUnknownFields:(PBUnknownFieldSet*) other;

- (PBUnknownFieldSet_Builder*) mergeFromCodedInputStream:(PBCodedInputStream*) input;
- (PBUnknownFieldSet_Builder*) mergeFromData:(NSData*) data;
- (PBUnknownFieldSet_Builder*) mergeFromInputStream:(NSInputStream*) input;

- (PBUnknownFieldSet_Builder*) mergeVarintField:(int32_t) number value:(int32_t) value;

- (BOOL) mergeFieldFrom:(int32_t) tag input:(PBCodedInputStream*) input;

- (PBUnknownFieldSet_Builder*) addField:(PBField*) field forNumber:(int32_t) number;

- (PBUnknownFieldSet_Builder*) clear;
- (PBUnknownFieldSet_Builder*) mergeField:(PBField*) field forNumber:(int32_t) number;

@end
