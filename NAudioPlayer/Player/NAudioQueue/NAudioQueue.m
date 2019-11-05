//
//  NAudioQueue.m
//  NAudioPlayer
//
//  Created by 泽娄 on 2019/9/22.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import "NAudioQueue.h"
#import "NAudioSession.h"
#include <pthread.h>

#define kNumberOfBuffers 3              //AudioQueueBuffer数量，一般指明为3
#define kAQBufSize 128 * 1024        //每个AudioQueueBuffer的大小 128 * 1024

#define Size_DefaultBufferSize 10 * 2048 // 默认缓冲区大小

#define BitRateEstimationMaxPackets 5000

#define KNum_Descs 512 //复用的包描述数量

#define kAQMaxPacketDescs 512    // Number of packet descriptions in our array

@interface NAudioQueue ()
{
    AudioQueueBufferRef audioQueueBuffer[kNumberOfBuffers];
    NSLock *_lock; /// 锁
    BOOL inUsed[kNumberOfBuffers];//标记当前buffer是否正在被使用
    UInt32 currBufferIndex;//当前使用的buffer的索引
    UInt32 currBufferFillOffset;//当前buffer已填充的数据量
    UInt32 currBufferPacketCount;//当前是第几个packet,  当前填充了多少帧
    AudioStreamPacketDescription audioStreamPacketDesc[KNum_Descs];
    
    double sampleRate;            // Sample rate of the file (used to compare with
                                // samples played by the queue for current playback
                                // time)
    double packetDuration;        // sample rate times frames per packet
    UInt32 packetBufferSize;
    size_t bytesFilled;                // how many bytes have been filled
    bool inuse[kNumberOfBuffers];            // flags to indicate that a buffer is still in use
    NSInteger buffersUsed;
    unsigned int fillBufferIndex;    // the index of the audioQueueBuffer that is being filled
    size_t packetsFilled;            // how many packets have been filled
    UInt64 processedPacketsCount;        // number of packets accumulated for bitrate estimation
    UInt64 processedPacketsSizeTotal;    // byte size of accumulated estimation packets
    AudioStreamPacketDescription packetDescs[kAQMaxPacketDescs];    // packet descriptions for enqueuing audio
    
    pthread_mutex_t queueBuffersMutex;            // a mutex to protect the inuse flags
    pthread_cond_t queueBufferReadyCondition;    // a condition varable for handling the inuse flags
    bool _started;
}

/// 该属性指明了音频数据的格式信息，返回的数据是一个AudioStreamBasicDescription结构
@property (nonatomic, assign, readwrite) AudioStreamBasicDescription audioStreamBasicDescription;

@property (nonatomic, assign, readwrite) AudioFileStreamID audioFileStreamID;

@property (nonatomic, assign, readwrite) AudioQueueRef audioQueue; /// audio queue实例

@end

@implementation NAudioQueue

- (instancetype)initWithFilePath:(NSString *)filePath
{
    self = [super init];
    if (self) {
        
    }return self;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self createAudioSession];
    }return self;
}

/// 音频文件描述信息
- (instancetype)initWithAudioDesc:(AudioStreamBasicDescription)audioDesc
                audioFileStreamID:(AudioFileStreamID)audioFileStreamID
{
    self = [super init];
    if (self) {
        _started = NO;
        currBufferIndex = 0;
        currBufferFillOffset = 0;
        currBufferPacketCount = 0;
        self.audioStreamBasicDescription = audioDesc;
        self.audioFileStreamID = audioFileStreamID;
        [self createAudioSession];
        [self createPthread];
        [self createAudioQueue];
    }return self;
}

- (void)createAudioSession
{
    [[NAudioSession sharedInstance] setCategory:AVAudioSessionModeMoviePlayback]; /// 支持视频、音频播放
    [[NAudioSession sharedInstance] setPreferredSampleRate:44100];
    [[NAudioSession sharedInstance] setActive:YES];
    [[NAudioSession sharedInstance] addRouteChangeListener];
}

- (void)createPthread
{
    // initialize a mutex and condition so that we can block on buffers in use.
    pthread_mutex_init(&queueBuffersMutex, NULL);
    pthread_cond_init(&queueBufferReadyCondition, NULL);
}

/*
 参数及返回说明如下：
 1. inFormat：该参数指明了即将播放的音频的数据格式
 2. inCallbackProc：该回调用于当AudioQueue已使用完一个缓冲区时通知用户，用户可以继续填充音频数据
 3. inUserData：由用户传入的数据指针，用于传递给回调函数
 4. inCallbackRunLoop：指明回调事件发生在哪个RunLoop之中，如果传递NULL，表示在AudioQueue所在的线程上执行该回调事件，一般情况下，传递NULL即可。
 5. inCallbackRunLoopMode：指明回调事件发生的RunLoop的模式，传递NULL相当于kCFRunLoopCommonModes，通常情况下传递NULL即可
 6. outAQ：该AudioQueue的引用实例，
 */
- (void)createAudioQueue
{
    sampleRate = self.audioStreamBasicDescription.mSampleRate;
    packetDuration = self.audioStreamBasicDescription.mFramesPerPacket / sampleRate;
    
    NSLog(@"createAudioQueue, sampleRate:%.2f, packetDuration:%.2f", sampleRate, packetDuration);
    
    OSStatus status;
    status = AudioQueueNewOutput(&_audioStreamBasicDescription, NAudioQueueOutputCallback, (__bridge void * _Nullable)(self), NULL, NULL, 0, &_audioQueue);
    
    if (status != noErr) {
        NSLog(@"AudioQueueNewOutput 失败");
        return;
    }
    
    NSLog(@"AudioQueueNewOutput 成功");

    // start the queue if it has not been started already
    // listen to the "isRunning" property
    status = AudioQueueAddPropertyListener(_audioQueue, kAudioQueueProperty_IsRunning, ASAudioQueueIsRunningCallback, (__bridge void * _Nullable)(self));
    
    if (status) {
        NSLog(@"AudioQueueNewOutput error");
        return;
    }
    
    #define kAQDefaultBufSize 2048    // Number of bytes in each audio queue buffer

    // get the packet size if it is available
    UInt32 sizeOfUInt32 = sizeof(UInt32);
    status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &packetBufferSize);
    if (status || packetBufferSize == 0)
    {
        status = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32, &packetBufferSize);
        if (status || packetBufferSize == 0)
        {
            // No packet size available, just use the default
            packetBufferSize = kAQDefaultBufSize;
        }
    }

    NSLog(@"packetBufferSize: %d", packetBufferSize);
    
    // allocate audio queue buffers
    for (unsigned int i = 0; i < kNumberOfBuffers; ++i){
        status = AudioQueueAllocateBuffer(_audioQueue, packetBufferSize, &audioQueueBuffer[i]);
        if (status){
            /// [self failWithErrorCode:AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED];
            NSLog(@"buffer alloc fail");
            return;
        }
    }
    
//    for (int i = 0; i < kNumberOfBuffers; i++) {
//        status = AudioQueueAllocateBuffer(_audioQueue, kAQBufSize, &audioQueueBuffer[i]);
//        inUsed[i] = NO; /// 默认都是未使用
//        if (status != noErr) {
//            NSLog(@"AudioQueueAllocateBuffer 失败!!!");
//            continue;
//        }
//    }
//
    NSLog(@"AudioQueueAllocateBuffer 成功!!!");

    // get the cookie size
    UInt32 cookieSize;
    Boolean writable;
    OSStatus ignorableError;
    ignorableError = AudioFileStreamGetPropertyInfo(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    if (ignorableError)
    {
        return;
    }

    // get the cookie data
    void* cookieData = calloc(1, cookieSize);
    ignorableError = AudioFileStreamGetProperty(_audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
    if (ignorableError)
    {
        return;
    }

    // set the cookie on the queue.
    ignorableError = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_MagicCookie, cookieData, cookieSize);
    free(cookieData);
    if (ignorableError)
    {
        return;
    }
    
    // 设置音量
    AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Volume, 1.0);
    
    //// [self createBuffer];
}

/*
 该方法的作用是为存放音频数据的缓冲区开辟空间

 参数及返回说明如下：
 1. inAQ：AudioQueue的引用实例
 2. inBufferByteSize：需要开辟的缓冲区的大小
 3. outBuffer：开辟的缓冲区的引用实例
 */
- (void)createBuffer
{
    OSStatus status;
    for (int i = 0; i < kNumberOfBuffers; i++) {
        status = AudioQueueAllocateBuffer(_audioQueue, kAQBufSize, &audioQueueBuffer[i]);
        inUsed[i] = NO; /// 默认都是未使用
        if (status != noErr) {
            NSLog(@"AudioQueueAllocateBuffer 失败!!!");
            continue;
        }
    }
    
    NSLog(@"AudioQueueAllocateBuffer 成功!!!");
}

/// 开始
- (void)start
{
    if (!_audioQueue) {
        NSLog(@"audioQueue is null!!!");
        return;
    }
    
    OSStatus status;
    /// 队列处理开始，此后系统开始自动调用回调(Callback)函数
    status = AudioQueueStart(_audioQueue, nil);
    
    if (status != noErr) {
        NSLog(@"AudioQueueStart 失败!!!");
    }
    
    NSLog(@"AudioQueueStart 成功!!!");
    
    /// 标记start始成功
    _started = YES;
}

/// 暂停
- (void)pause
{
    if (!_audioQueue) {
        NSLog(@"audioQueue is null!!!");
        return;
    }
    
    OSStatus status= AudioQueuePause(_audioQueue);
    if (status!= noErr){
//        [self.audioProperty error:LLYAudioError_AQ_PauseFail];
        return;
    }
}

/// 停止
- (void)stop
{
    if (!_audioQueue) {
        NSLog(@"audioQueue is null!!!");
        return;
    }

    if (_audioQueue) {
        OSStatus status= AudioQueueStop(_audioQueue, true);
        if (status!= noErr){
//            [self.audioProperty error:LLYAudioError_AQ_StopFail];
            return;
        }
    }
}

- (void)playData:(NSData *)data
       inputData:(nonnull const void *)inputData
 inNumberPackets:(UInt32)inNumberPackets
packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions
           isEof:(BOOL)isEof
{
    [_lock lock];
    
    if (packetDescriptions == NULL) {
        NSLog(@"packetDescriptions is null");
    }
    
//    NSLog(@"data length: %lu, inNumberPackets: %d", [data length], inNumberPackets); /// 2048
    
    OSStatus status;
    
    for (int i = 0; i < inNumberPackets; ++i) {
        /// 获取 AudioStreamPacketDescription对象
        AudioStreamPacketDescription packetDesc = packetDescriptions[i];
        SInt64 packetOffset = packetDesc.mStartOffset;
        SInt64 packetSize = packetDesc.mDataByteSize;
        size_t bufSpaceRemaining;
        
        NSLog(@"processedPacketsCount: %llu", processedPacketsCount);
        NSLog(@"packetSize: %llu, packetBufferSize: %d", packetSize, packetBufferSize);

        if (processedPacketsCount < BitRateEstimationMaxPackets) {
            processedPacketsSizeTotal += packetSize;
            processedPacketsCount += 1;
        }
        
        @synchronized (self) {
            
            if (packetSize > packetBufferSize) {
                NSLog(@"fuffer too small");
            }
            
            bufSpaceRemaining = packetBufferSize - bytesFilled;
        }
        
        if (bufSpaceRemaining < packetSize) {
            NSLog(@"bufSpaceRemaining < packetSize。bufSpaceRemaining:%zu, packetSize:%lld", bufSpaceRemaining, packetSize);

            [self enqueueBuffer];
        }
        
        @synchronized(self)
        {
            // If there was some kind of issue with enqueueBuffer and we didn't
            // make space for the new audio data then back out
            //
            if (bytesFilled + packetSize > packetBufferSize){
                return;
            }
            // copy data to the audio queue buffer
            AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
            memcpy((char*)fillBuf->mAudioData + bytesFilled, (const char*)inputData + packetOffset, packetSize);

            // fill out packet description
            packetDescs[packetsFilled] = packetDescriptions[i];
            packetDescs[packetsFilled].mStartOffset = bytesFilled;
            // keep track of bytes filled and packets filled
            bytesFilled += packetSize;
            packetsFilled += 1;
        }
        
        // if that was the last free packet description, then enqueue the buffer.
        size_t packetsDescsRemaining = kAQMaxPacketDescs - packetsFilled;
        if (packetsDescsRemaining == 0) {
            [self enqueueBuffer];
        }
        
    }
    [_lock unlock];
}

- (void)enqueueBuffer
{
    @synchronized(self){
        inuse[fillBufferIndex] = true;        // set in use flag
        buffersUsed++;
        OSStatus status;
        // enqueue buffer
        AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
        fillBuf->mAudioDataByteSize = bytesFilled;
        if (packetsFilled){
            status = AudioQueueEnqueueBuffer(_audioQueue, fillBuf, packetsFilled, packetDescs);
        }else{
            status = AudioQueueEnqueueBuffer(_audioQueue, fillBuf, 0, NULL);
        }
        
        NSLog(@"buffersUsed: %ld", (long)buffersUsed);
        
        if (buffersUsed == kNumberOfBuffers - 1){
             status = AudioQueueStart(_audioQueue, NULL);
            NSLog(@"播放开始, status: %d", status);
        }
        // go to next buffer
        if (++fillBufferIndex >= kNumberOfBuffers) fillBufferIndex = 0;
        bytesFilled = 0;        // reset bytes filled
        packetsFilled = 0;        // reset packets filled
    }

    // wait until next buffer is not in use
    pthread_mutex_lock(&queueBuffersMutex);
    while (inuse[fillBufferIndex]){
        pthread_cond_wait(&queueBufferReadyCondition, &queueBuffersMutex);
    }
    pthread_mutex_unlock(&queueBuffersMutex);
}

- (void)p_putBufferToQueue
{
    inUsed[currBufferIndex] = YES;
    
    AudioQueueBufferRef outBufferRef = audioQueueBuffer[currBufferIndex];
    
    OSStatus error;

    if (currBufferPacketCount > 0) {
        NSLog(@"currBufferPacketCount > 0 ");
        error = AudioQueueEnqueueBuffer(_audioQueue, outBufferRef, currBufferPacketCount, audioStreamPacketDesc);
    }else{
        NSLog(@"currBufferPacketCount <= 0 ");

        error = AudioQueueEnqueueBuffer(_audioQueue, outBufferRef, 0, NULL);
    }
    
    if (error != noErr) {
        /// [_audioProperty error:LLYAudioError_AQB_EnqueueFail];
        return;
    }
    
//    if (_audioProperty.status != LLYAudioStatus_Playing) {
//        _audioProperty.status = LLYAudioStatus_Playing;
//    }
    
    if (!_started) {
        [self start];
    }
    
    /// [self start];
    
    currBufferIndex = ++currBufferIndex % kNumberOfBuffers;
    
    NSLog(@"currBufferIndex: %u", (unsigned int)currBufferIndex);
    
    currBufferPacketCount = 0;
    
    /// 当前buffer已填充的数据量恢复为0
    currBufferFillOffset = 0;
    
    /// while (inUsed[currBufferIndex]);
    while (inUsed[currBufferIndex]) {
        /// NSLog(@"一直循环");
    }
}

#pragma mark private method

- (void)p_audioQueueOutput:(AudioQueueRef)inAQ inBuffer:(AudioQueueBufferRef)inBuffer
{
//    for (int i = 0; i < kNumberOfBuffers; i++) {
//
//        if (inBuffer == audioQueueBuffer[i]) {
//            [_lock lock];
//            /// // 将这个 buffer 设为未使用
//            inUsed[i] = NO;
//            NSLog(@"当前buffer_%d的数据已经播放完了 还给程序继续装数据去吧！！！！！！",i);
//            [_lock unlock];
//        }
//    }
    
        unsigned int bufIndex = -1;
        for (unsigned int i = 0; i < kNumberOfBuffers; ++i){
            if (inBuffer == audioQueueBuffer[i]){
               NSLog(@"当前buffer_%d的数据已经播放完了 还给程序继续装数据去吧！！！！！！",i);
                bufIndex = i;
                break;
            }
        }
        
        if (bufIndex == -1)
        {
//            [self failWithErrorCode:AS_AUDIO_QUEUE_BUFFER_MISMATCH];
            pthread_mutex_lock(&queueBuffersMutex);
            pthread_cond_signal(&queueBufferReadyCondition);
            pthread_mutex_unlock(&queueBuffersMutex);
            return;
        }
        
        // signal waiting thread that the buffer is free.
        pthread_mutex_lock(&queueBuffersMutex);
        inuse[bufIndex] = false;
        buffersUsed--;

    //
    //  Enable this logging to measure how many buffers are queued at any time.
    //
    #if LOG_QUEUED_BUFFERS
        NSLog(@"Queued buffers: %ld", buffersUsed);
    #endif
        
        pthread_cond_signal(&queueBufferReadyCondition);
        pthread_mutex_unlock(&queueBuffersMutex);
}

/*
    该回调用于当AudioQueue已使用完一个缓冲区时通知用户，用户能够继续填充音频数据
 */
static void NAudioQueueOutputCallback(void *inUserData, AudioQueueRef inAQ,
                                        AudioQueueBufferRef buffer){
        
    NAudioQueue *_audioQueue = (__bridge NAudioQueue *)inUserData;
    
    // OSStatus status;
    
//    NSLog(@"audioQueue 回调");
    
    [_audioQueue p_audioQueueOutput:inAQ inBuffer:buffer];
    
    /*
    /// 读取包数据
    UInt32 numBytes = buffer->mAudioDataBytesCapacity;
    UInt32 numPackets = _audioQueue->numPacketsToRead;
    
    status = AudioFileReadPacketData(_audioQueue->audioFileID, NO, &numBytes, _audioQueue->packetDescs, _audioQueue->packetIndex,&numPackets, buffer->mAudioData);
    
    if (status != noErr) {
        NSLog(@"AudioFileReadPackets 失败");
        return;
    }
    
    NSLog(@"读取包数据, status: %d", status);
    
    //成功读取时
    if (numPackets>0) {
        //将缓冲的容量设置为与读取的音频数据一样大小(确保内存空间)
        buffer->mAudioDataByteSize = numBytes;
        //完成给队列配置缓存的处理
        status = AudioQueueEnqueueBuffer(_audioQueue->audioQueue, buffer, numPackets, _audioQueue->packetDescs);
        //移动包的位置
        _audioQueue->packetIndex += numPackets;
        
        /// 标识播放状态
        _audioQueue.playing = YES;
    }
     */
}


static void ASAudioQueueIsRunningCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    NAudioQueue *_streamer = (__bridge NAudioQueue *)inUserData;
    [_streamer handlePropertyChangeForQueue:inAQ propertyID:inID];
}

- (void)handlePropertyChangeForQueue:(AudioQueueRef)inAQ
    propertyID:(AudioQueuePropertyID)inID
{
    @autoreleasepool {
//        if (![[NSThread currentThread] isEqual:internalThread])
//        {
//            [self
//                performSelector:@selector(handlePropertyChange:)
//                onThread:internalThread
//                withObject:[NSNumber numberWithInt:inID]
//                waitUntilDone:NO
//                modes:[NSArray arrayWithObject:NSDefaultRunLoopMode]];
//            return;
//        }
        @synchronized(self)
        {
            if (inID == kAudioQueueProperty_IsRunning)
            {
                UInt32 isRunning = 0;
                UInt32 size = sizeof(UInt32);
                AudioQueueGetProperty(_audioQueue, inID, &isRunning, &size);
                NSLog(@"监听audioQueue播放状态");
//                if (state == AS_STOPPING)
//                {
//                    // Should check value of isRunning to ensure this kAudioQueueProperty_IsRunning isn't
//                    // the *start* of a very short stream
//                    UInt32 isRunning = 0;
//                    UInt32 size = sizeof(UInt32);
//                    AudioQueueGetProperty(audioQueue, inID, &isRunning, &size);
//                    if (isRunning == 0)
//                    {
//                        self.state = AS_STOPPED;
//                    }
//                }
//                else if (state == AS_WAITING_FOR_QUEUE_TO_START)
//                {
//                    //
//                    // Note about this bug avoidance quirk:
//                    //
//                    // On cleanup of the AudioQueue thread, on rare occasions, there would
//                    // be a crash in CFSetContainsValue as a CFRunLoopObserver was getting
//                    // removed from the CFRunLoop.
//                    //
//                    // After lots of testing, it appeared that the audio thread was
//                    // attempting to remove CFRunLoop observers from the CFRunLoop after the
//                    // thread had already deallocated the run loop.
//                    //
//                    // By creating an NSRunLoop for the AudioQueue thread, it changes the
//                    // thread destruction order and seems to avoid this crash bug -- or
//                    // at least I haven't had it since (nasty hard to reproduce error!)
//                    //
//                    [NSRunLoop currentRunLoop];
//
//                    self.state = AS_PLAYING;
//                }
//                else
//                {
//                    NSLog(@"AudioQueue changed state in unexpected way.");
//                }
            }
        }
    }
}
@end
