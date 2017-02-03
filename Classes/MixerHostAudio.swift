import AudioToolbox
import AVFoundation

typealias MyAudioUnitSampleType = Int32
let kMyAudioFormatFlagsAudioUnit =
        kAudioFormatFlagIsSignedInteger |
        kAudioFormatFlagsNativeEndian |
        kAudioFormatFlagIsPacked |
        kAudioFormatFlagIsNonInterleaved |
        (AudioFormatFlags(kAudioUnitSampleFractionBits) << kLinearPCMFormatFlagsSampleFractionShift)

// Data structure for mono or stereo sound, to pass to the application's render callback function,
// which gets invoked by a Mixer unit input bus when it needs more audio to play.

//MARK: - Structs
struct SoundStruct {
    
    // set to true if there is data in the audioDataRight member
    var isStereo: Bool = false
    
    // the total number of frames in the audio data
    var frameCount: UInt32 = 0
    
    // the next audio sample to play
    var sampleNumber: UInt32 = 0
    
    // the complete left (or mono) channel of audio data read from an audio file
    var audioDataLeft: UnsafeMutablePointer<MyAudioUnitSampleType>? = nil
    
    // the complete right channel of audio data read from an audio file
    var audioDataRight: UnsafeMutablePointer<MyAudioUnitSampleType>? = nil
    
}




//MARK: - Mixer Input Bus Render Callback

/*
    This callback is invoked each time a Multichannel Mixer unit input bus requires more audio samples. In this app, the mixer unit has two input buses. Each of them has its own render callback function and its own interleaved audio data buffer to read from.
 
    This callback is written for an inRefCon parameter that can point to two noninterleaved buffers (for a stereo sound) or to one mono buffer (for a mono sound).
 
    Audio unit input render callbacks are invoked on a realtime priority thread (the highest priority on the system). To work well, to not make the system unresponsive, and to avoid audio artifacts, a render callback must not:

        * allocate memory
        * access the file system or a network connection
        * take locks
        * waste time

    In addition, it's usually best to avoid sending Objective-C messages in a render callback.
*/

private func inputRenderCallback(
    
    // A pointer to a struct containing the complete audio data to play, as well as state information such as the first sample to play on this invocation of the callback.
    
    inRefCon: UnsafeMutableRawPointer,
    
    // Unused here. When generating audio, use ioActionFlags to indicate silence between sounds, for silence, also memset the ioData buffers to 0.
    
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    
    // Unused here.
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    
    // The mixer unit input bus that is requesting some new
    inBusNumber: UInt32,
    
    // Frames of audio data to play. The number of frames of audio to provide to the buffer(s)
    
    inNumberFrames: UInt32,
    
    // Pointed to by the ioData parameter. On output, the audio data to play. The callback's primary responsibility is to fill the buffer(s) in the AudioBufferList.
    
    ioData: UnsafeMutablePointer<AudioBufferList>?
    
    ) -> OSStatus {
    
    //http://stackoverflow.com/questions/39547504/convert-unsafemutablerawpointer-to-unsafemutablepointert-in-swift-3
    
    //create opaque pointer to help convert unsaferawpointer to unsafepointer<T>
    let soundStructOpaquePtr:OpaquePointer = OpaquePointer(inRefCon)
    let soundStructPointerArray:UnsafeMutablePointer<SoundStruct> = UnsafeMutablePointer<SoundStruct>(soundStructOpaquePtr)
    
    //grab vars from array
    let frameTotalForSound = Int(soundStructPointerArray[Int(inBusNumber)].frameCount)
    let isStereo = soundStructPointerArray[Int(inBusNumber)].isStereo
    
    // Declare variables to point to the audio buffers. Their data type must match the buffer data type.
    var dataInLeft: UnsafeMutablePointer<MyAudioUnitSampleType>? = nil
    var dataInRight: UnsafeMutablePointer<MyAudioUnitSampleType>? = nil
    
    dataInLeft = soundStructPointerArray[Int(inBusNumber)].audioDataLeft
    if (isStereo) {
        dataInRight = soundStructPointerArray[Int(inBusNumber)].audioDataRight
    }
    
    //if ioData can be converted to a UMABLP
    if let ioPtr:UnsafeMutableAudioBufferListPointer = UnsafeMutableAudioBufferListPointer(ioData) {
        
        // Establish pointers to the memory into which the audio from the buffers should go. This reflects the fact that each Multichannel Mixer unit input bus has two channels, as specified by this app's graphStreamFormat variable.
        
        var outSamplesChannelLeft: UnsafeMutablePointer<MyAudioUnitSampleType>? = nil
        var outSamplesChannelRight: UnsafeMutablePointer<MyAudioUnitSampleType>? = nil
        
        //if left channel mData is valid...
        if (ioPtr[0].mData != nil){
            //create opaque pointers to help convert unsaferawpointer to unsafepointer<T>
            let mDataOpaquePointer0:OpaquePointer = OpaquePointer(ioPtr[0].mData!)
            outSamplesChannelLeft = UnsafeMutablePointer<MyAudioUnitSampleType>(mDataOpaquePointer0)
            
        } else {
            print("Render callback: invalid mData in left channel")
        }
        
        //if track is in stereo
        if (isStereo) {
            
            //and right channel mData is valid...
            if (ioPtr[1].mData != nil){
                let mDataOpaquePointer1:OpaquePointer = OpaquePointer(ioPtr[1].mData!)
                outSamplesChannelRight = UnsafeMutablePointer<MyAudioUnitSampleType>(mDataOpaquePointer1)
            } else {
                print("Render callback: invalid mData in right channel")
            }
    
        }
        
        // Get the sample number, as an index into the sound stored in memory, to start reading data from.
        var sampleNumber = Int(soundStructPointerArray[Int(inBusNumber)].sampleNumber)
        
        //check all the optionals
        var leftOK:Bool = false
        var rightOK:Bool = false
        
        if (dataInLeft != nil && outSamplesChannelLeft != nil){
            leftOK = true
        }
       
        if (isStereo) {
            
            //only check if stereo
            if(dataInRight != nil && outSamplesChannelRight != nil){
                rightOK = true
            }
            
        } else {
            rightOK = true
        }
        
        //if all the optionals are valid...
        if (leftOK && rightOK){
            
            // Fill the buffer or buffers pointed at by *ioData with the requested number of samples of audio from the sound stored in memory.
            for frameNumber in 0..<Int(inNumberFrames) {
                
                outSamplesChannelLeft![frameNumber] = dataInLeft![sampleNumber]
                if (isStereo) {outSamplesChannelRight![frameNumber]  = dataInRight![sampleNumber]}
                
                //move to next sample
                sampleNumber += 1
                
                // After reaching the end of the sound stored in memory--that is, after (frameTotalForSound / inNumberFrames) invocations of this callback--loop back to the start of the sound so playback resumes from there.
                if sampleNumber >= frameTotalForSound {sampleNumber = 0}
            }
            
            // Update the stored sample number so, the next time this callback is invoked, playback resumes at the correct spot.
            soundStructPointerArray[Int(inBusNumber)].sampleNumber = UInt32(sampleNumber)
            
        } else {
            print("Render callabck: left or right channel had invalid data")
        }
        
    } else {
        print("Render callabck: Error getting pointer for ioData")
    }
    
    return noErr
    
}

class MixerHostAudio: NSObject {
    
    //MARK: - Variables
    let NUM_FILES:Int = 2
    
    /// sample rate to use throughout audio processing chain
    var graphSampleRate: Float64 = 0
    private var sourceURLArray: [NSURL]!
    private var soundStructArray:UnsafeMutablePointer<SoundStruct> = UnsafeMutablePointer<SoundStruct>.allocate(capacity: 2)
    
    // Before using an AudioStreamBasicDescription struct you must initialize it to 0. However, because these ASBDs are declared in external storage, they are automatically initialized to 0. Auto generated initializer initializes all elements to 0.
    
    /// stream formats for use in buffer and mixer input
    var stereoStreamFormat: AudioStreamBasicDescription = AudioStreamBasicDescription()
    var monoStreamFormat: AudioStreamBasicDescription = AudioStreamBasicDescription()
    
    private var processingGraph: AUGraph? = nil
    /// Boolean flag to indicate whether audio is playing or not
    var playing: Bool = false
    /// Boolean flag to indicate whether audio was playing when an interruption arrived
    var interruptedDuringPlayback: Bool = false
    /// the Multichannel Mixer unit
    var mixerUnit: AudioUnit? = nil
    
    
    //MARK: -
    //MARK: Audio route change listener callback
    
    // Audio session callback function for responding to audio route changes. If playing back audio and the user unplugs a headset or headphones, or removes the device from a dock connector for hardware that supports audio playback, this callback detects that and stops playback. Refer to AudioSessionPropertyListener in Audio Session Services Reference.
    
    internal func handleRouteChange(notification: NSNotification) {
        
        // Ensure that this callback was invoked because of an audio route change
        guard notification.name == NSNotification.Name.AVAudioSessionRouteChange else {return}
        
        // This callback, being outside the implementation block, needs a reference to the MixerHostAudio object, which it receives in the inUserData parameter. You provide this reference when registering this callback (see the call to AudioSessionAddPropertyListener).
        
        let audioObject = self
        
        // if application sound is not playing, there's nothing to do, so return.
        guard audioObject.playing else {
            
            print("Audio route change while application audio is stopped.")
            return
            
        }
        
        // Determine the specific type of audio route change that occurred.
        let routeChangeDictionary = notification.userInfo!
        
        let routeChangeReasonRef = routeChangeDictionary[AVAudioSessionRouteChangeReasonKey]
        
        let routeChangeReason = routeChangeReasonRef as! UInt
        
        // "Old device unavailable" indicates that a headset or headphones were unplugged, or thatnthe device was removed from a dock connector that supports audio output. In such a case, pause or stop audio (as advised by the iOS Human Interface Guidelines)
        
        if routeChangeReason == AVAudioSessionRouteChangeReason.oldDeviceUnavailable.rawValue {
            
            print("Audio output device was removed, stopping audio playback.")
            
            let notification:String = "MixerHostAudioObjectPlaybackStateDidChangeNotification"
            NotificationCenter.default.post(
                name: NSNotification.Name(rawValue: notification),
                object: audioObject)
            
        } else {
            
            print("A route change occurred that does not require stopping application audio.")
        }
    }

    
    //MARK: - Initialize
    
    // Get the app ready for playback.
    override init() {
        
        super.init()
        
        self.interruptedDuringPlayback = false
        
        self.setupAudioSession()
        self.obtainSoundFileURLs()
        self.setupStreamFormats()
        self.readAudioFilesIntoMemory()
        self.configureAndInitializeAudioProcessingGraph()
        
    }
    
    
    //MARK: - Audio set up
    
    private func setupAudioSession() {
        
        let mySession = AVAudioSession.sharedInstance()
        
        // Specify that this object is the delegate of the audio session, so that this object's endInterruption method will be invoked when needed. The delegate property is deprecated. Instead, you should register for the NSNotifications named below.
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(MixerHostAudio.handleInterruption(notification:)),
            name: NSNotification.Name.AVAudioSessionInterruption,
            object: mySession)
        
        // Assign the Playback category to the audio session.
        do {
            try mySession.setCategory(AVAudioSessionCategoryPlayback)
            
        } catch _ {
            
            print("Error setting audio session category.")
            return
        }
        
        // Request the desired hardware sample rate.
        self.graphSampleRate = 44100.0
        
        do {
            try mySession.setPreferredSampleRate(graphSampleRate)
            
        } catch _ {
            
            print("Error setting preferred hardware sample rate.")
            return
        }
        
        // Activate the audio session
        do {
            try mySession.setActive(true)
            
        } catch _ {
            
            print("Error activating audio session during initial setup.")
            return
        }
        
        // Obtain the actual hardware sample rate and store it for later use in the audio processing graph.
        self.graphSampleRate = mySession.sampleRate
        
        // Register the audio route change listener callback function with the audio session.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(MixerHostAudio.handleRouteChange(notification:)),
            name: NSNotification.Name.AVAudioSessionRouteChange,
            object: mySession)
    }
    
    
    private func obtainSoundFileURLs() {
        
        // Create the URLs for the source audio files. 
        let guitarLoop = Bundle.main.url(forResource: "guitarStereo", withExtension: "caf")!
        
        let beatsLoop = Bundle.main.url(forResource: "beatsMono", withExtension: "caf")!
        
        // ExtAudioFileRef objects expect NSURLs, so cast to NSURL here
        sourceURLArray = [guitarLoop as NSURL, beatsLoop as NSURL]
    }
    
    private func setupStreamFormats(){
        
        monoStreamFormat = setupStreamFormat(withChannels:1)
        stereoStreamFormat = setupStreamFormat(withChannels:2)
        
    }
    
    private func setupStreamFormat(withChannels:UInt32) -> AudioStreamBasicDescription {
        
        var asbd:AudioStreamBasicDescription = AudioStreamBasicDescription()
        
        // The AudioUnitSampleType data type is the recommended type for sample data in audio units. This obtains the byte size of the type for use in filling in the ASBD.
        
        let bytesPerSample = UInt32(MemoryLayout<MyAudioUnitSampleType>.stride)
        
        // Fill the application audio format struct's fields to define a linear PCM, stereo, noninterleaved stream at the hardware sample rate.
        
        asbd.mFormatID          = kAudioFormatLinearPCM
        asbd.mFormatFlags       = kMyAudioFormatFlagsAudioUnit
        asbd.mBytesPerPacket    = bytesPerSample
        asbd.mFramesPerPacket   = 1
        asbd.mBytesPerFrame     = bytesPerSample
        asbd.mChannelsPerFrame  = withChannels
        asbd.mBitsPerChannel    = 8 * bytesPerSample
        asbd.mSampleRate        = graphSampleRate
        
        print("Set up stream format with channels:", withChannels)
        self.printASBD(asbd: asbd)
        
        return asbd
        
    }
    
    
    //MARK: -
    //MARK: Read audio files into memory
    
    private func readAudioFilesIntoMemory() {
        
        for (audioFile, sourceURL) in sourceURLArray.enumerated() {
            
            print("readAudioFilesIntoMemory", Int32(audioFile))
            
            // Instantiate an extended audio file object.
            var audioFileObject: ExtAudioFileRef? = nil
            
            // Open an audio file and associate it with the extended audio file object.
            var result = ExtAudioFileOpenURL(sourceURL, &audioFileObject)
            
            guard result == noErr else {
                self.printErrorMessage(
                    errorString: "ExtAudioFileOpenURL",
                    withStatus: result)
                return
            }
            
            // Get the audio file's length in frames.
            var totalFramesInFile: UInt64 = 0
            var frameLengthPropertySize = UInt32(MemoryLayout.size(ofValue: totalFramesInFile))
            
            result = ExtAudioFileGetProperty(
                audioFileObject!,
                kExtAudioFileProperty_FileLengthFrames,
                &frameLengthPropertySize,
                &totalFramesInFile
            )
            
            guard result == noErr else {
                self.printErrorMessage(
                    errorString: "ExtAudioFileGetProperty (audio file length in frames)",
                    withStatus: result)
                return
            }
            
            // Assign the frame count to the soundStructArray instance variable
            soundStructArray[audioFile].frameCount = UInt32(totalFramesInFile)
            
            // Get the audio file's number of channels.
            var fileAudioFormat: AudioStreamBasicDescription = AudioStreamBasicDescription()
            var formatPropertySize = UInt32(MemoryLayout.stride(ofValue: fileAudioFormat))
            
            result = ExtAudioFileGetProperty(
                audioFileObject!,
                kExtAudioFileProperty_FileDataFormat,
                &formatPropertySize,
                &fileAudioFormat
            )
            
            guard result == noErr else {
                self.printErrorMessage(
                    errorString: "ExtAudioFileGetProperty (file audio format)",
                    withStatus: result)
                return
            }
            
            let channelCount = fileAudioFormat.mChannelsPerFrame
            
            // Allocate memory in the soundStructArray instance variable to hold the left channel, or mono, audio data
            soundStructArray[audioFile].audioDataLeft =
                UnsafeMutablePointer<MyAudioUnitSampleType>.allocate(capacity: Int(totalFramesInFile))
            
            var importFormat = AudioStreamBasicDescription()
            if channelCount == 2 {
                
                soundStructArray[audioFile].isStereo = true
                // Sound is stereo, so allocate memory in the soundStructArray instance variable to hold the right channel audio data
                soundStructArray[audioFile].audioDataRight =
                    UnsafeMutablePointer<MyAudioUnitSampleType>.allocate(capacity: Int(totalFramesInFile))
                importFormat = stereoStreamFormat
                
            } else if channelCount == 1 {
                
                soundStructArray[audioFile].isStereo = false
                importFormat = monoStreamFormat
                
            } else {
                
                print("*** WARNING: File format not supported - wrong number of channels")
                ExtAudioFileDispose(audioFileObject!)
                return
            }
            
            // Assign the appropriate mixer input bus stream data format to the extended audio file object. This is the format used for the audio data placed into the audio buffer in the SoundStruct data structure, which is in turn used in the inputRenderCallback callback function.
            
            result =    ExtAudioFileSetProperty(
                audioFileObject!,
                kExtAudioFileProperty_ClientDataFormat,
                UInt32(MemoryLayout.stride(ofValue: importFormat)),
                &importFormat
            )
            
            guard result == noErr else {
                self.printErrorMessage(
                    errorString: "ExtAudioFileSetProperty (client data format)",
                    withStatus: result)
                return
            }
            
            // Set up an AudioBufferList struct, which has two roles:
            //
            //        1. It gives the ExtAudioFileRead function the configuration it
            //            needs to correctly provide the data to the buffer.
            //
            //        2. It points to the soundStructArray[audioFile].audioDataLeft buffer, so
            //            that audio data obtained from disk using the ExtAudioFileRead function
            //            goes to that buffer
            
            // Allocate memory for the buffer list struct according to the number of
            //    channels it represents.
            let bufferList = AudioBufferList.allocate(maximumBuffers: Int(channelCount))
            
            // initialize the mNumberBuffers member
            print(bufferList.count)
            
            // initialize the mBuffers member to 0
            let emptyBuffer:AudioBuffer = AudioBuffer()
            for arrayIndex in 0..<Int(channelCount) {
                bufferList[arrayIndex] = emptyBuffer
            }
            
            // set up the AudioBuffer structs in the buffer list
            bufferList[0].mNumberChannels = 1
            bufferList[0].mDataByteSize = UInt32(totalFramesInFile) * UInt32(MemoryLayout<MyAudioUnitSampleType>.stride)
            bufferList[0].mData = UnsafeMutableRawPointer(soundStructArray[audioFile].audioDataLeft)
            
            if channelCount == 2 {
                bufferList[1].mNumberChannels = 1
                bufferList[1].mDataByteSize = UInt32(totalFramesInFile) * UInt32(MemoryLayout<MyAudioUnitSampleType>.stride)
                bufferList[1].mData = UnsafeMutableRawPointer(soundStructArray[audioFile].audioDataRight)
            }
            
            // Perform a synchronous, sequential read of the audio data out of the file and
            //    into the soundStructArray[audioFile].audioDataLeft and (if stereo) .audioDataRight members.
            var numberOfPacketsToRead = UInt32(totalFramesInFile)
            
            print("numberOfPacketsToRead=", Int32(numberOfPacketsToRead))
            result = ExtAudioFileRead(
                audioFileObject!,
                &numberOfPacketsToRead,
                bufferList.unsafeMutablePointer
            )
            
            free(bufferList.unsafeMutablePointer)
            
            guard result == noErr else {
                
                self.printErrorMessage(errorString: "ExtAudioFileRead failure - ", withStatus: result)
                
                // If reading from the file failed, then free the memory for the sound buffer.
                soundStructArray[audioFile].audioDataLeft?.deallocate(capacity: Int(totalFramesInFile))
                soundStructArray[audioFile].audioDataLeft = nil
                
                if channelCount == 2 {
                    soundStructArray[audioFile].audioDataLeft?.deallocate(capacity: Int(totalFramesInFile))
                    soundStructArray[audioFile].audioDataRight = nil
                }
                
                ExtAudioFileDispose(audioFileObject!)
                return
            }
            
            print("Finished reading file %i into memory", Int32(audioFile))
            
            // Set the sample index to zero, so that playback starts at the
            //    beginning of the sound.
            soundStructArray[audioFile].sampleNumber = 0
            
            // Dispose of the extended audio file object, which also
            //    closes the associated file.
            ExtAudioFileDispose(audioFileObject!)
        }
    }
    
    
    //MARK: -
    //MARK: Audio processing graph setup
    
    // This method performs all the work needed to set up the audio processing graph:
    
    // 1. Instantiate and open an audio processing graph
    // 2. Obtain the audio unit nodes for the graph
    // 3. Configure the Multichannel Mixer unit
    //     * specify the number of input buses
    //     * specify the output sample rate
    //     * specify the maximum frames-per-slice
    // 4. Initialize the audio processing graph
    
    private func configureAndInitializeAudioProcessingGraph() {
        
        print("Configuring and then initializing audio processing graph")
        var result = noErr
        
        //............................................................................
        // Create a new audio processing graph.
        result = NewAUGraph(&processingGraph)
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "NewAUGraph", withStatus: result)
            return
        }
        
        
        //............................................................................
        // Specify the audio unit component descriptions for the audio units to be
        //    added to the graph.
        
        // I/O unit
        var iOUnitDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        
        // Multichannel mixer unit
        var MixerUnitDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Mixer,
            componentSubType: kAudioUnitSubType_MultiChannelMixer,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        
        
        //............................................................................
        // Add nodes to the audio processing graph.
        print("Adding nodes to audio processing graph")
        
        var iONode: AUNode = 0         // node for I/O unit
        var mixerNode: AUNode = 0      // node for Multichannel Mixer unit
        
        // Add the nodes to the audio processing graph
        result = AUGraphAddNode(
            processingGraph!,
            &iOUnitDescription,
            &iONode)
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AUGraphNewNode failed for I/O unit", withStatus: result)
            return
        }
        
        
        result = AUGraphAddNode(
            processingGraph!,
            &MixerUnitDescription,
            &mixerNode
        )
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AUGraphNewNode failed for Mixer unit", withStatus: result)
            return
        }
        
        
        //............................................................................
        // Open the audio processing graph
        
        // Following this call, the audio units are instantiated but not initialized
        //    (no resource allocation occurs and the audio units are not in a state to
        //    process audio).
        result = AUGraphOpen(processingGraph!)
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AUGraphOpen", withStatus: result)
            return
        }
        
        
        //............................................................................
        // Obtain the mixer unit instance from its corresponding node.
        
        result =    AUGraphNodeInfo(
            processingGraph!,
            mixerNode,
            nil,
            &mixerUnit
        )
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AUGraphNodeInfo", withStatus: result)
            return
        }
        
        
        //............................................................................
        // Multichannel Mixer unit Setup
        
        var busCount: UInt32   = 2    // bus count for mixer unit input
        let guitarBus: UInt32  = 0    // mixer unit bus 0 will be stereo and will take the guitar sound
        let beatsBus: UInt32   = 1    // mixer unit bus 1 will be mono and will take the beats sound
        
        print("Setting mixer unit input bus count to: %u", busCount)
        result = AudioUnitSetProperty(
            mixerUnit!,
            kAudioUnitProperty_ElementCount,
            kAudioUnitScope_Input,
            0,
            &busCount,
            UInt32(MemoryLayout.size(ofValue: busCount))
        )
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AudioUnitSetProperty (set mixer unit bus count)", withStatus: result)
            return
        }
        
        
        print("Setting kAudioUnitProperty_MaximumFramesPerSlice for mixer unit global scope")
        // Increase the maximum frames per slice allows the mixer unit to accommodate the
        //    larger slice size used when the screen is locked.
        var maximumFramesPerSlice: UInt32 = 4096
        
        result = AudioUnitSetProperty(
            mixerUnit!,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maximumFramesPerSlice,
            UInt32(MemoryLayout.size(ofValue: maximumFramesPerSlice))
        )
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AudioUnitSetProperty (set mixer unit input stream format)", withStatus: result)
            return
        }
        
        
        // Attach the input render callback and context to each input bus
        for busNumber in 0..<busCount {
            
            // Setup the struture that contains the input render callback
            
            var inputCallbackStruct = AURenderCallbackStruct(
                inputProc: inputRenderCallback,
                inputProcRefCon: soundStructArray)
        
        
            print("Registering the render callback with mixer unit input bus %u", busNumber)
            // Set a callback for the specified node's specified input
            result = AUGraphSetNodeInputCallback(
                processingGraph!,
                mixerNode,
                busNumber,
                &inputCallbackStruct
            )
            
            guard result == noErr else {
                self.printErrorMessage(errorString: "AUGraphSetNodeInputCallback", withStatus: result)
                return
            }
        }
        
        
        print("Setting stereo stream format for mixer unit \"guitar\" input bus")
        result = AudioUnitSetProperty(
            mixerUnit!,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            guitarBus,
            &stereoStreamFormat,
            UInt32(MemoryLayout.size(ofValue: stereoStreamFormat))
        )
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AudioUnitSetProperty (set mixer unit guitar input bus stream format)", withStatus: result)
            return
        }
        
        
        print("Setting mono stream format for mixer unit \"beats\" input bus")
        result = AudioUnitSetProperty(
            mixerUnit!,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            beatsBus,
            &monoStreamFormat,
            UInt32(MemoryLayout.size(ofValue: monoStreamFormat))
        )
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AudioUnitSetProperty (set mixer unit beats input bus stream format)", withStatus: result)
            return
        }
        
        
        print("Setting sample rate for mixer unit output scope")
        // Set the mixer unit's output sample rate format. This is the only aspect of the output stream
        //    format that must be explicitly set.
        result = AudioUnitSetProperty(
            mixerUnit!,
            kAudioUnitProperty_SampleRate,
            kAudioUnitScope_Output,
            0,
            &graphSampleRate,
            UInt32(MemoryLayout.size(ofValue: graphSampleRate))
        )
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AudioUnitSetProperty (set mixer unit output stream format)", withStatus: result)
            return
        }
        
        
        //............................................................................
        // Connect the nodes of the audio processing graph
        print("Connecting the mixer output to the input of the I/O unit output element")
        
        result = AUGraphConnectNodeInput (
            processingGraph!,
            mixerNode,         // source node
            0,                 // source node output bus number
            iONode,            // destination node
            0                  // desintation node input bus number
        )
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AUGraphConnectNodeInput", withStatus: result)
            return
        }
        
        
        //............................................................................
        // Initialize audio processing graph
        
        // Diagnostic code
        // Call CAShow if you want to look at the state of the audio processing
        //    graph.
        print("Audio processing graph state immediately before initializing it:")
        CAShow(UnsafeMutablePointer(processingGraph!))
        
        print("Initializing the audio processing graph")
        // Initialize the audio processing graph, configure audio data stream formats for
        //    each input and output, and validate the connections between audio units.
        result = AUGraphInitialize(processingGraph!)
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AUGraphInitialize", withStatus: result)
            return
        }
    }
    
    
    //MARK: -
    //MARK: Playback control
    
    // Start playback
    func startAUGraph() {
        
        print("Starting audio processing graph")
        let result = AUGraphStart(processingGraph!)
        guard result == noErr else {
            self.printErrorMessage(errorString: "AUGraphStart", withStatus: result)
            return
        }
        
        self.playing = true
    }
    
    // Stop playback
    func stopAUGraph() {
        
        print("Stopping audio processing graph")
        var isRunning: DarwinBoolean = false
        var result = AUGraphIsRunning(processingGraph!, &isRunning)
        guard result == noErr else {
            self.printErrorMessage(errorString: "AUGraphIsRunning", withStatus: result)
            return
        }
        
        if (isRunning.boolValue) {
            
            result = AUGraphStop(processingGraph!)
            guard result == noErr else {
                self.printErrorMessage(errorString: "AUGraphStop", withStatus: result)
                return
            }
            self.playing = false
        }
    }
    
    
    //MARK: -
    //MARK: Mixer unit control
    // Enable or disable a specified bus
    func enableMixerInput(inputBus: UInt32, isOn isOnValue: Bool) {
        
        print("Bus %d now %@", Int32(inputBus), isOnValue ? "on" : "off")
        
        let result = AudioUnitSetParameter(
            mixerUnit!,
            kMultiChannelMixerParam_Enable,
            kAudioUnitScope_Input,
            inputBus,
            isOnValue ? 1 : 0,
            0
        )
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AudioUnitSetParameter (enable the mixer unit)", withStatus: result)
            return
        }
        
        
        // Ensure that the sound loops stay in sync when reenabling an input bus
        if inputBus == 0 && isOnValue {
            soundStructArray[0].sampleNumber = soundStructArray[1].sampleNumber
        }
        
        if inputBus == 1 && isOnValue {
            soundStructArray[1].sampleNumber = soundStructArray[0].sampleNumber
        }
    }
    
    
    // Set the mixer unit input volume for a specified bus
    func setMixerInput(inputBus: UInt32, gain newGain: AudioUnitParameterValue) {
        
        /*
        This method does *not* ensure that sound loops stay in sync if the user has
        moved the volume of an input channel to zero. When a channel's input
        level goes to zero, the corresponding input render callback is no longer
        invoked. Consequently, the sample number for that channel remains constant
        while the sample number for the other channel continues to increment. As a
        workaround, the view controller Nib file specifies that the minimum input
        level is 0.01, not zero.
        
        The enableMixerInput:isOn: method in this class, however, does ensure that the
        loops stay in sync when a user disables and then reenables an input bus.
        */
        let result = AudioUnitSetParameter(
            mixerUnit!,
            kMultiChannelMixerParam_Volume,
            kAudioUnitScope_Input,
            inputBus,
            newGain,
            0
        )
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AudioUnitSetParameter (set mixer unit input volume)", withStatus: result)
            return
        }
        
    }
    
    
    // Set the mxer unit output volume
    func setMixerOutputGain(newGain: AudioUnitParameterValue) {
        
        let result = AudioUnitSetParameter(
            mixerUnit!,
            kMultiChannelMixerParam_Volume,
            kAudioUnitScope_Output,
            0,
            newGain,
            0
        )
        
        guard result == noErr else {
            self.printErrorMessage(errorString: "AudioUnitSetParameter (set mixer unit output volume)", withStatus: result)
            return
        }
        
    }
    
    
    //MARK: -
    //MARK: Audio Session Delegate Methods
    internal func handleInterruption(notification: NSNotification) {
        let type = notification.userInfo![AVAudioSessionInterruptionTypeKey] as! UInt
        switch AVAudioSessionInterruptionType(rawValue: type)! {
            // Respond to having been interrupted. This method sends a notification to the
            //    controller object, which in turn invokes the playOrStop: toggle method. The
            //    interruptedDuringPlayback flag lets the  endInterruptionWithFlags: method know
            //    whether playback was in progress at the time of the interruption.
        case .began:
            
            print("Audio session was interrupted.")
            
            if playing {
                
                self.interruptedDuringPlayback = true
                
                let MixerHostAudioObjectPlaybackStateDidChangeNotification = "MixerHostAudioObjectPlaybackStateDidChangeNotification"
                NotificationCenter.default.post(name: NSNotification.Name(rawValue: MixerHostAudioObjectPlaybackStateDidChangeNotification), object: self)
            }
            
            
            // Respond to the end of an interruption. This method gets invoked, for example,
            //    after the user dismisses a clock alarm.
        case .ended:
            let rawFlags = notification.userInfo![AVAudioSessionInterruptionOptionKey] as! UInt
            let flags = AVAudioSessionInterruptionOptions(rawValue: rawFlags)
            
            // Test if the interruption that has just ended was one from which this app
            //    should resume playback.
            if flags.contains(.shouldResume) {
                
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    
                } catch _ {
                    
                    print("Unable to reactivate the audio session after the interruption ended.")
                    return
                    
                }
                
                print("Audio session reactivated after interruption.")
                
                if interruptedDuringPlayback {
                    
                    self.interruptedDuringPlayback = false
                    
                    // Resume playback by sending a notification to the controller object, which
                    //    in turn invokes the playOrStop: toggle method.
                    let MixerHostAudioObjectPlaybackStateDidChangeNotification = "MixerHostAudioObjectPlaybackStateDidChangeNotification"
                    NotificationCenter.default.post(name: NSNotification.Name(rawValue: MixerHostAudioObjectPlaybackStateDidChangeNotification), object: self)
                    
                }
            }
        }
    }
    
    
    //MARK: -
    //MARK: Utility methods
    
    // You can use this method during development and debugging to look at the
    //    fields of an AudioStreamBasicDescription struct.
    private func printASBD(asbd: AudioStreamBasicDescription) {
        
        let formatIDString = asbd.mFormatID.fourCharString
        
        NSLog("  Sample Rate:         %10.0f",  asbd.mSampleRate)
        NSLog("  Format ID:                 %@",    formatIDString)
        NSLog("  Format Flags:        %10X",    asbd.mFormatFlags)
        NSLog("  Bytes per Packet:    %10d",    asbd.mBytesPerPacket)
        NSLog("  Frames per Packet:   %10d",    asbd.mFramesPerPacket)
        NSLog("  Bytes per Frame:     %10d",    asbd.mBytesPerFrame)
        NSLog("  Channels per Frame:  %10d",    asbd.mChannelsPerFrame)
        NSLog("  Bits per Channel:    %10d",    asbd.mBitsPerChannel)
    }
    
    
    private func printErrorMessage(errorString: String, withStatus result: OSStatus) {
        
        let resultString = FourCharCode(bitPattern: result).possibleFourCharString
        
        print(
            "*** %@ error: %d %08X %@\n",
            errorString,
            result, result, resultString
        )
    }
    
    
    //MARK: -
    //MARK: Deallocate
    
    deinit {
        
        for audioFile in 0..<NUM_FILES {
            
            let totalFramesInFile = soundStructArray[audioFile].frameCount
            if soundStructArray[audioFile].audioDataLeft != nil {
                soundStructArray[audioFile].audioDataLeft?.deallocate(capacity: Int(totalFramesInFile))
                soundStructArray[audioFile].audioDataLeft = nil
            }
            
            if soundStructArray[audioFile].audioDataRight != nil {
                soundStructArray[audioFile].audioDataRight?.deallocate(capacity: Int(totalFramesInFile))
                soundStructArray[audioFile].audioDataRight = nil
            }
            soundStructArray.deallocate(capacity: 2)
        }
        
    }
    
}
