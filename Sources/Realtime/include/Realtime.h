#pragma once
#include <CoreAudio/CoreAudio.h>
#include <stdint.h>
typedef struct SBQueue SBQueue;
/** Allocate a bounded SPSC stereo queue off the realtime thread. */
SBQueue * _Nullable sb_create(uint32_t capacity);
/** Free only after the producer and consumer have both stopped. */
void sb_destroy(SBQueue * _Nonnull queue);
/** Copy float32 buffers without allocation or locks; drop incoming excess frames. */
void sb_push(SBQueue * _Nonnull queue, const AudioBufferList * _Nonnull input);
/** Consume interleaved stereo frames; only the single consumer may call this. */
uint32_t sb_read(SBQueue * _Nonnull queue, float * _Nonnull output, uint32_t capacity);
/** Consumer discards older unread frames before copying the newest bounded window. */
uint32_t sb_read_latest(SBQueue * _Nonnull queue, float * _Nonnull output, uint32_t capacity);
/** Read diagnostic counters without accessing mutable PCM storage. */
uint64_t sb_callbacks(SBQueue * _Nonnull queue);
uint64_t sb_dropped(SBQueue * _Nonnull queue);
/** Core Audio callback that only copies input to the preallocated queue. */
OSStatus sb_io(AudioObjectID device, const AudioTimeStamp * _Nonnull now, const AudioBufferList * _Nonnull input,
 const AudioTimeStamp * _Nonnull inputTime, AudioBufferList * _Nonnull output, const AudioTimeStamp * _Nonnull outputTime, void * _Nullable context);
