// SPDX-License-Identifier: MPL-2.0
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#include "Realtime.h"
#include <assert.h>
#include <stdio.h>
/** Exercise FIFO ownership, stereo phase preservation, overflow, and planar input. */
int main(void) {
 SBQueue *q=sb_create(4); assert(q);
 float stereo[]={1,-1,2,-2,3,-3,4,-4,5,-5}, out[12]={0};
 AudioBufferList b={.mNumberBuffers=1,.mBuffers={{2,sizeof(stereo),stereo}}};
 sb_push(q,&b); assert(sb_dropped(q)==1); assert(sb_callbacks(q)==1);
 assert(sb_read(q,out,2)==2); assert(out[0]==1 && out[1]==-1 && out[2]==2);
 assert(sb_read(q,out,6)==2); assert(out[0]==3 && out[2]==4); assert(sb_read(q,out,6)==0);
 struct { UInt32 count; AudioBuffer buffers[2]; } planar={2,{{1,8,stereo},{1,8,stereo+2}}};
 sb_push(q,(const AudioBufferList *)&planar);
 assert(sb_read(q,out,6)==2); assert(out[0]==1 && out[1]==2 && out[2]==-1 && out[3]==-2);
 sb_push(q,&b);
 assert(sb_read_latest(q,out,2)==2); assert(out[0]==3 && out[2]==4);
 assert(sb_dropped(q)==4);
 sb_destroy(q); puts("PASS: FIFO, overflow, empty, stereo phase, planar input");
}
