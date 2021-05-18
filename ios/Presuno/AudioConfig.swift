struct AudioConfig {
    var sampleRate: Double // AVAudioSession.sharedInstance().sampleRate
    var channelCount: Int
    var bitrate: Int
    
    init(sampleRate: Double, channelCount: Int, bitrate: Int) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitrate = bitrate
    }
}
