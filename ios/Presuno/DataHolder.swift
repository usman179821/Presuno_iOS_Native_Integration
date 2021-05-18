class DataHolder {
    
    static let sharedInstance = DataHolder() // Singleton pattern in Swift
    private init() {
        // This prevents others from using the default '()' initializer for this class.
    }

    public var id: Int64 = 0
    var connecion: BaseConnection?
}
