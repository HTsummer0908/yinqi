// SPDX-License-Identifier: MPL-2.0
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#include "Realtime.h"
#include <pthread.h>
#include <stdatomic.h>
#include <assert.h>
#include <stdio.h>
static SBQueue *queue;
static _Atomic int finished;
/** Emit monotonically increasing paired channel values under sustained overflow. */
static void *producer(void *unused) {
 for(int i=1;i<=200000;i++) {
  float input[2]={(float)i,-(float)i};
  AudioBufferList b={.mNumberBuffers=1,.mBuffers={{2,sizeof(input),input}}};
  sb_push(queue,&b);
 }
 atomic_store(&finished,1); return NULL;
}
/** Verify that concurrent publication never tears a stereo pair or reorders a retained frame. */
int main(void) {
 queue=sb_create(64); pthread_t thread; pthread_create(&thread,NULL,producer,NULL);
 float output[34],previous=0; unsigned long read=0;
 for(;;) {
  unsigned n=sb_read_latest(queue,output,17);
  for(unsigned i=0;i<n;i++) { assert(output[i*2]>previous); assert(output[i*2]==-output[i*2+1]);previous=output[i*2];read++; }
  if(n==0 && atomic_load(&finished)) { n=sb_read_latest(queue,output,17); if(n==0)break; for(unsigned i=0;i<n;i++) {assert(output[i*2]>previous);assert(output[i*2]==-output[i*2+1]);previous=output[i*2];read++;} }
 }
 pthread_join(thread,NULL); assert(read+sb_dropped(queue)==200000);
 sb_destroy(queue); puts("PASS: concurrent SPSC 200000 stereo frames, exact retained+dropped accounting");
}
