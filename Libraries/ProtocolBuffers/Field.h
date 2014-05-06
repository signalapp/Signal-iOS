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

@class PBCodedOutputStream;

@interface PBField : NSObject {
@protected
  NSMutableArray* mutableVarintList;
  NSMutableArray* mutableFixed32List;
  NSMutableArray* mutableFixed64List;
  NSMutableArray* mutableLengthDelimitedList;
  NSMutableArray* mutableGroupList;
}

- (NSArray*) varintList;
- (NSArray*) fixed32List;
- (NSArray*) fixed64List;
- (NSArray*) lengthDelimitedList;
- (NSArray*) groupList;

+ (PBField*) defaultInstance;

- (void) writeTo:(int32_t) fieldNumber
          output:(PBCodedOutputStream*) output;

- (int32_t) getSerializedSize:(int32_t) fieldNumber;
- (void) writeAsMessageSetExtensionTo:(int32_t) fieldNumber
                               output:(PBCodedOutputStream*) output;
- (int32_t) getSerializedSizeAsMessageSetExtension:(int32_t) fieldNumber;

@end
