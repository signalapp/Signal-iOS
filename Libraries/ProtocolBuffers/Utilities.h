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

int64_t convertFloat64ToInt64(Float64 f);
int32_t convertFloat32ToInt32(Float32 f);
Float64 convertInt64ToFloat64(int64_t f);
Float32 convertInt32ToFloat32(int32_t f);

uint64_t convertInt64ToUInt64(int64_t i);
int64_t  convertUInt64ToInt64(uint64_t u);
uint32_t convertInt32ToUInt32(int32_t i);
int64_t  convertUInt32ToInt32(uint32_t u);

int32_t logicalRightShift32(int32_t value, int32_t spaces);
int64_t logicalRightShift64(int64_t value, int32_t spaces);
