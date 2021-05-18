import CocoaLumberjackSwift


class BitrateHistory {
    var ts: CFTimeInterval
    var bitrate: Double
    
    init(ts: CFTimeInterval, bitrate: Double) {
        self.ts = ts
        self.bitrate = bitrate
    }
}

class TrafficHistory {
    var values: [Int64]
    var pos = 0
    let capacity: Int
    var prev: Int64
    init(capacity: Int = 10) {
        self.capacity = capacity
        values = Array<Int64>()
        prev = 0
    }
    
    func put(_ value: Int64) {
        let delta = value > prev ? value - prev : 0
        if values.count < capacity {
            values.append(delta)
        } else {
            values[pos] = delta
        }
        pos = (pos + 1) % capacity
        prev = value
    }
    
    var last: Int64 {
        return values.isEmpty ? 0 : values[(pos+capacity-1) % capacity]
    }
    
    func avg() -> Double {
        if values.isEmpty { return 0.0 }
        let sum = values.reduce(0) { $0 + $1 }
        return Double(sum) / Double(values.count)
    }
}

class StreamStats {
    
    var avgSent: TrafficHistory
    var avgDelivered: TrafficHistory
    var totalSent: UInt64 = 0
    var totalDelivered: UInt64 = 0
    var prevLatency: Double = 0.0
    var lastLatency: Double = 0.0
    var momentaryLatency: Double = 0.0

    init(capacity: Int) {
        avgSent = TrafficHistory(capacity: capacity)
        avgDelivered = TrafficHistory(capacity: capacity)
    }
    
    func put(sent: UInt64, delivered: UInt64) {
        //DDLogInfo("Stream stats sent \(sent) delivered \(delivered)")
        avgSent.put(Int64(sent))
        avgDelivered.put(Int64(delivered))
        totalSent = sent
        totalDelivered = delivered
    }
    
    func getLatency(interval: TimeInterval) -> Double {
        guard interval > 0 else { return 0.0 }
        let deliveredBps = (avgDelivered.avg() / interval)
        let queued = totalSent > totalDelivered ? totalSent - totalDelivered : 0
        let latency = deliveredBps > 0 ? Double(queued) / deliveredBps : 0
        //DDLogInfo("delivered \(deliveredBps) Bps queued \(queued) latency \(latency)")
        prevLatency = lastLatency
        lastLatency = latency
        return latency
    }
}


protocol StreamConditioner {
    func start(bitrate: Int, id: [Int32])
    func stop()
    func addConnection(id: Int32)
    func removeConnection(id: Int32)
}

class StreamConditionerBase: StreamConditioner {
    
    var currentBitrate: Double = 0
    var bitrateHistory: [BitrateHistory] = []
    internal var stats: [Int32: StreamStats]

    var connectionId:Set<Int32> = []
    
    var checkTimer: Timer?
    
    weak var streamer: Streamer?
    let lock = NSLock()
    
    init(streamer: Streamer) {
        self.streamer = streamer
        connectionId = []
        stats = [:]
    }
    
    deinit {
        self.checkTimer?.invalidate()
    }
    
    func start(bitrate: Int, id: [Int32]) {
        guard id.count > 0 else {
            return
        }
        for i in id {
            stats[i] = StreamStats(capacity: 10)
        }
        currentBitrate = Double(bitrate)
        connectionId = Set(id)
        
        let curTime = CACurrentMediaTime()
        bitrateHistory.append(BitrateHistory(ts: curTime, bitrate: currentBitrate))
        
        checkTimer?.invalidate()
        
        let firstTime = Date(timeIntervalSinceNow: checkDelay())
        checkTimer = Timer(fire: firstTime,
                           interval: checkInterval(),
                           repeats: true,
                           block: { [weak self] (timer) in
                            guard self?.streamer != nil else {
                                timer.invalidate()
                                return
                            }
                            self?.checkNetwork()
                           })
        RunLoop.main.add(checkTimer!, forMode: .common)
            
    }
    
    func checkNetwork() {
        guard lock.try() else {
            return
        }
        guard streamer != nil, !connectionId.isEmpty else {
            lock.unlock()
            return
        }
        for id in connectionId {
            let sent = streamer?.bytesSent(connection: id) ?? 0
            let delivered = streamer?.bytesDelivered(connection: id) ?? 0
            stats[id]?.put(sent: sent, delivered: delivered)
        }
        check()
        lock.unlock()
    }
    
    func stop() {
        lock.lock()
        checkTimer?.invalidate()
        stats.removeAll()
        connectionId.removeAll()
        lock.unlock()
    }
    
    func addConnection(id: Int32) {
        guard id >= 0 else { return}
        lock.lock()
        connectionId.insert(id)
        stats[id] = StreamStats(capacity: 10)
        lock.unlock()
    }
    
    func removeConnection(id: Int32) {
        lock.lock()
        connectionId.remove(id)
        stats.removeValue(forKey: id)
        lock.unlock()

    }

    func check() {
        
    }

    func changeBitrate(newBitrate: Double) {
        let curTime = CACurrentMediaTime()
        bitrateHistory.append(BitrateHistory(ts: curTime, bitrate: newBitrate))
        streamer?.changeBitrate(newBitrate: Int32(newBitrate))
        currentBitrate = newBitrate
    }
    
    func changeBitrateQuiet(newBitrate: Double) {
        streamer?.changeBitrate(newBitrate: Int32(newBitrate))
    }
    
    func checkInterval() -> TimeInterval {
        return 0.5
    }
    
    func checkDelay() -> TimeInterval {
        return 1
    }
    
}

class StreamConditionerMode1: StreamConditionerBase {
    
    let NORMALIZATION_DELAY: CFTimeInterval = 5.0 // Ignore lost packets during this time after bitrate change
    let MAX_LATENCY: Double = 1.0 //Maximal allowed latency (latency is calculated as delta between sent and delivered divided by delivery rate)
    let RECOVERY_ATTEMPT_INTERVAL: CFTimeInterval = 60
    
    var initBitrate: Double = 0
    var minBitrate: Double = 0
    
    override func start(bitrate: Int, id: [Int32]) {
        initBitrate = Double(bitrate)
        minBitrate = initBitrate / 4
        super.start(bitrate: bitrate, id: id)
    }
    
    override func check() {
        if let prevBitrate = bitrateHistory.last, let firstBitrate = bitrateHistory.first {

            let curTime = CACurrentMediaTime()
            let lastChange = prevBitrate.ts
            var maxLatency: Double = 0.0
            var latencyDecreasing = true
            for (_,s) in stats {
                let latency = s.getLatency(interval: checkInterval())
                maxLatency = Double.maximum(latency, maxLatency)
                if s.prevLatency < latency {
                    latencyDecreasing = false
                }
            }
            //DDLogInfo("latency \(maxLatency), decreasing: \(latencyDecreasing)")

            if maxLatency > MAX_LATENCY {
                let dtChange = curTime - prevBitrate.ts
                if latencyDecreasing && maxLatency < MAX_LATENCY * 10 {
                    return
                }
                if prevBitrate.bitrate <= minBitrate || dtChange < NORMALIZATION_DELAY {
                    return
                }
                let newBitrate = max(minBitrate, prevBitrate.bitrate * 1000 / 1414)
                changeBitrate(newBitrate: newBitrate)

            } else if prevBitrate.bitrate != firstBitrate.bitrate &&
                curTime - lastChange >= RECOVERY_ATTEMPT_INTERVAL &&
                latencyDecreasing {
                let newBitrate = min(initBitrate, prevBitrate.bitrate * 1415 / 1000)
                changeBitrate(newBitrate: newBitrate)
            }
        }
    }
    
}

class StreamConditionerMode2: StreamConditionerBase {
    
    let NORMALIZATION_DELAY: CFTimeInterval = 2 // Ignore lost packets during this time after bitrate change
    let MAX_LATENCY: Double = 0.5 //Maximal allowed latency (latency is calculated as delta between sent and delivered divided by delivery rate)
    let BANDWITH_STEPS: [Double] = [0.2, 0.25, 1.0 / 3.0, 0.450, 0.600, 0.780, 1.000]
    let RECOVERY_ATTEMPT_INTERVALS: [CFTimeInterval] = [15, 60, 60 * 3]
    let DROP_MERGE_INTERVAL: CFTimeInterval // Period for bitrate drop duration
    
    var fullSpeed: Double = 0
    var step = 0
    
    override init(streamer: Streamer) {
        DROP_MERGE_INTERVAL = CFTimeInterval(BANDWITH_STEPS.count) * NORMALIZATION_DELAY * 2
        super.init(streamer: streamer)
    }
    
    override func start(bitrate: Int, id: [Int32]) {
        fullSpeed = Double(bitrate)
        step = 2
        let startBitrate = round(fullSpeed * BANDWITH_STEPS[step])
        super.start(bitrate: Int(startBitrate), id: id)
        changeBitrateQuiet(newBitrate: startBitrate)
    }
    
    override func check() {
        if let prevBitrate = bitrateHistory.last {
            let curTime = CACurrentMediaTime()
            var maxLatency: Double = 0.0
            var latencyDecreasing = true
            
            for (_,s) in stats {
                let latency = s.getLatency(interval: checkInterval())
                maxLatency = Double.maximum(latency, maxLatency)
                if s.prevLatency < latency {
                    latencyDecreasing = false
                }
            }

            if maxLatency > MAX_LATENCY {
                if latencyDecreasing && maxLatency < MAX_LATENCY * 10 {
                    return
                }

                let dtChange = curTime - prevBitrate.ts
                if step == 0 || dtChange < NORMALIZATION_DELAY {
                    return
                }
                step = step - 1
                let newBitrate = round(fullSpeed * BANDWITH_STEPS[step])
                changeBitrate(newBitrate: newBitrate)
            } else if Double(prevBitrate.bitrate) < fullSpeed &&
                latencyDecreasing && canTryToRecover() {
                step = step + 1
                let newBitrate = round(fullSpeed * BANDWITH_STEPS[step])
                changeBitrate(newBitrate: newBitrate)
            }
        }
    }
    
    func canTryToRecover() -> Bool {
        let curTime = CACurrentMediaTime()
        let len = bitrateHistory.count
        var numDrops = 0
        let numIntervals = RECOVERY_ATTEMPT_INTERVALS.count
        var prevDropTime: CFTimeInterval = 0
        
        for i in stride(from: len-1, to: 0, by: -1) {
            let last = bitrateHistory[i]
            let prev = bitrateHistory[i-1]
            let dt = curTime - last.ts
            if last.bitrate < prev.bitrate {
                if prevDropTime != 0, prevDropTime - last.ts < DROP_MERGE_INTERVAL {
                    continue
                }
                if dt <= RECOVERY_ATTEMPT_INTERVALS[numDrops] {
                    return false
                }
                numDrops = numDrops + 1
                prevDropTime = last.ts
            }
            
            if numDrops == numIntervals || curTime - last.ts >= RECOVERY_ATTEMPT_INTERVALS[numIntervals - 1] {
                break
            }
        }
        return true
    }
    
    override func checkInterval() -> TimeInterval {
        return 2
    }
    
    override func checkDelay() -> TimeInterval {
        return 2
    }
    
}


class StreamConditionerMode3: StreamConditionerBase {
    
    let NORMALIZATION_DELAY: CFTimeInterval = 5 // Ignore lost packets during this time after bitrate change
    let MIN_RECOVER_LATENCY: Double = 0.1
    let RECOVERY_ATTEMPT_INTERVAL: CFTimeInterval = 60
    let RECOVERY_STEP_INTERVAL: CFTimeInterval = 15

    private var initBitrate: Double = 0
    private var minBitrate: Double = 0

    override func start(bitrate: Int, id: [Int32]) {
        initBitrate = Double(bitrate)
        minBitrate = initBitrate * 0.25
        super.start(bitrate: bitrate, id: id)
    }
    
    override func check() {
        guard connectionId.count > 0 else {
            return
        }
        var newBitrate: Double = initBitrate
        var maxLatency: Double = 0.0
        for id in connectionId {
            let sent = stats[id]?.totalSent ?? 0
            let delivered = stats[id]?.totalDelivered ?? 0
            let sentBps = ((stats[id]?.avgSent.avg() ?? 0.0) / checkInterval())
            let deliveredBps = ((stats[id]?.avgDelivered.avg() ?? 0.0) / checkInterval())
            let queued = sent > delivered ?  sent - delivered : 0
            let queuedSec = Double(queued) / deliveredBps
            maxLatency = Double.maximum(queuedSec, maxLatency)
            //DDLogInfo("Queued \(queued) Bitrate \(deliveredBps) / \(sentBps) Latency \(maxLatency)")
            var reducedBitrate = currentBitrate
            if deliveredBps < currentBitrate * 0.98 && deliveredBps < sentBps && queuedSec > 0.1  {
                let ratio = deliveredBps / sentBps
                reducedBitrate = ((currentBitrate * ratio) / 100000).rounded(.down) * 100000
                //DDLogInfo("set ratio \(ratio) : \(currentBitrate) -> \(reducedBitrate)")
            } else if queuedSec > 0.5 {
                reducedBitrate = currentBitrate * 0.8
                //DDLogInfo("set ratio 0.8")
            }
            if reducedBitrate < newBitrate {
                newBitrate = Double.maximum(reducedBitrate, minBitrate)
            }
        }
        guard let prevBitrate = bitrateHistory.last else { return }
        let curTime = CACurrentMediaTime()
        let dtChange = curTime - prevBitrate.ts
        if dtChange < NORMALIZATION_DELAY {
            return
        }

        if newBitrate >= currentBitrate && maxLatency < MIN_RECOVER_LATENCY  && currentBitrate < initBitrate && canTryToRecover() {
            newBitrate = currentBitrate + Double.minimum(500000, initBitrate * 0.1)
        }
        if (currentBitrate - newBitrate).magnitude > 100000 {
            changeBitrate(newBitrate: newBitrate)
        }
    }
    
    func canTryToRecover() -> Bool {
        let curTime = CACurrentMediaTime()
        guard bitrateHistory.count > 1 else {return false}
        let i = bitrateHistory.count - 1
        let last = bitrateHistory[i]
        let prev = bitrateHistory[i-1]
        if  last.bitrate < prev.bitrate && curTime - last.ts > RECOVERY_ATTEMPT_INTERVAL {
            //First step after drop
            return true
        } else if  last.bitrate > prev.bitrate && curTime - last.ts > RECOVERY_STEP_INTERVAL {
            //Continue restoring bitrate
            return true
        }
        return false
    }
    
    override func checkInterval() -> TimeInterval {
        return 0.5
    }
    
    override func checkDelay() -> TimeInterval {
        return 1
    }
    
}
