// SPDX-License-Identifier: MPL-2.0
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#include "Realtime.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
struct SBQueue { float *pcm; uint32_t capacity; _Atomic uint64_t write, read, callbacks, dropped; };
/** Storage is allocated once before AudioDeviceStart. */
SBQueue *sb_create(uint32_t capacity) {
 if (!capacity) return NULL;
 SBQueue *q=calloc(1,sizeof(*q)); if (!q) return NULL;
 q->pcm=calloc((size_t)capacity*2,sizeof(float)); q->capacity=capacity;
 if (!q->pcm) { free(q); return NULL; } return q;
}
/** Caller has already stopped IO and consumption. */
void sb_destroy(SBQueue *q) { if(q) { free(q->pcm); free(q); } }
/** Release/acquire transfers slot ownership; overflow drops NEW input, never a reader's slot.
 * A 4096-frame queue bounds latency to 85 ms at 48 kHz; consumer drains every 20 ms.
 */
void sb_push(SBQueue *q,const AudioBufferList *b) {
 atomic_fetch_add_explicit(&q->callbacks,1,memory_order_relaxed);
 if(!b || !b->mNumberBuffers || !b->mBuffers[0].mData) return;
 const AudioBuffer *a=&b->mBuffers[0];
 if(a->mNumberChannels!=1 && a->mNumberChannels!=2) return;
 uint32_t frames=a->mDataByteSize/(sizeof(float)*a->mNumberChannels);
 bool planar=a->mNumberChannels==1 && b->mNumberBuffers>=2;
 if(planar && (!b->mBuffers[1].mData || b->mBuffers[1].mDataByteSize/4<frames)) return;
 uint64_t w=atomic_load_explicit(&q->write,memory_order_relaxed), r=atomic_load_explicit(&q->read,memory_order_acquire);
 uint32_t room=q->capacity-(uint32_t)(w-r), count=frames<room?frames:room;
 const float *left=a->mData, *right=planar?b->mBuffers[1].mData:NULL;
 for(uint32_t i=0;i<count;i++) {
  uint32_t slot=(uint32_t)((w+i)%q->capacity)*2;
  q->pcm[slot]=left[i*a->mNumberChannels];
  q->pcm[slot+1]=planar?right[i]:(a->mNumberChannels==2?left[i*2+1]:left[i]);
 }
 atomic_store_explicit(&q->write,w+count,memory_order_release);
 atomic_fetch_add_explicit(&q->dropped,frames-count,memory_order_relaxed);
}
/** Reader publishes released slots only after the copy finishes. */
uint32_t sb_read(SBQueue *q,float *out,uint32_t capacity) {
 uint64_t r=atomic_load_explicit(&q->read,memory_order_relaxed),w=atomic_load_explicit(&q->write,memory_order_acquire);
 uint32_t n=(uint32_t)(w-r); if(n>capacity)n=capacity;
 for(uint32_t i=0;i<n;i++) memcpy(out+i*2,q->pcm+((r+i)%q->capacity)*2,2*sizeof(float));
 atomic_store_explicit(&q->read,r+n,memory_order_release); return n;
}
/** Return an atomic counter, never a PCM snapshot. */
uint64_t sb_callbacks(SBQueue *q){return atomic_load_explicit(&q->callbacks,memory_order_relaxed);}
/** Return the number of discarded incoming frames. */
uint64_t sb_dropped(SBQueue *q){return atomic_load_explicit(&q->dropped,memory_order_relaxed);}
/** C callback avoids Swift ARC, closures, allocation, locks, and UI work. */
OSStatus sb_io(AudioObjectID d,const AudioTimeStamp *n,const AudioBufferList *i,const AudioTimeStamp *it,AudioBufferList *o,const AudioTimeStamp *ot,void *c){sb_push(c,i);return noErr;}
/** 2026-09-11: Only the consumer releases old slots; producer never overwrites a slot being read.
 * Discarding queued backlog here favors freshness after worker stalls without violating SPSC ownership.
 */
uint32_t sb_read_latest(SBQueue *q,float *out,uint32_t capacity) {
 uint64_t r=atomic_load_explicit(&q->read,memory_order_relaxed), w=atomic_load_explicit(&q->write,memory_order_acquire);
 uint64_t available=w-r;
 if(available>capacity) {
  uint64_t skipped=available-capacity;
  atomic_store_explicit(&q->read,r+skipped,memory_order_release);
  atomic_fetch_add_explicit(&q->dropped,skipped,memory_order_relaxed);
 }
 return sb_read(q,out,capacity);
}
