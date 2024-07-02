import Foundation

public protocol AllowedUserDefaultTypes {}

/* // This one is more painful than helpful
extension Bool: AllowedUserDefaultTypes {}
extension String: AllowedUserDefaultTypes {}
extension Int: AllowedUserDefaultTypes {}
extension Int32: AllowedUserDefaultTypes {}
extension Double: AllowedUserDefaultTypes {}
extension Float: AllowedUserDefaultTypes {}
extension Data: AllowedUserDefaultTypes {}
extension URL: AllowedUserDefaultTypes {}
//extension Dictionary<String, Any>: AllowedUserDefaultTypes {}
extension Array: AllowedUserDefaultTypes where Element: AllowedUserDefaultTypes {}
*/

// Does not support Optional types due to caching
@propertyWrapper
public class UserDefault<T> /*where T: AllowedUserDefaultTypes*/ {
    public let key: String
    public let userDefaults: UserDefaults
    private var cachedValue: T?
    
    public init(key: String, userDefaults: UserDefaults = .standard) {
        self.key = key
        self.userDefaults = userDefaults
    }
    
    public var wrappedValue: T {
        get {
            #if DEBUG && false
            SGtrace("UD.\(key)", what: "GET")
            #endif
            
            if let strongCachedValue = cachedValue {
                #if DEBUG && false
                SGtrace("UD", what: "CACHED \(key) \(strongCachedValue)")
                #endif
                return strongCachedValue
            }
            
            cachedValue = readFromUserDefaults()
            
            #if DEBUG
            SGtrace("UD.\(key)", what: "EXTRACTED: \(cachedValue!)")
            #endif
            return cachedValue!
        }
        set {
            cachedValue = newValue
            #if DEBUG
            SGtrace("UD.\(key)", what: "CACHE UPDATED \(cachedValue!)")
            #endif
            userDefaults.set(newValue, forKey: key)
        }
    }
    
    fileprivate func readFromUserDefaults() -> T {
        switch T.self {
        case is Bool.Type:
            return (userDefaults.bool(forKey: key) as! T)
        case is String.Type:
            return (userDefaults.string(forKey: key) as! T)
        case is Int32.Type:
            return (Int32(exactly: userDefaults.integer(forKey: key)) as! T)
        case is Int.Type:
            return (userDefaults.integer(forKey: key) as! T)
        case is Double.Type:
            return (userDefaults.double(forKey: key) as! T)
        case is Float.Type:
            return (userDefaults.float(forKey: key) as! T)
        case is Data.Type:
            return (userDefaults.data(forKey: key) as! T)
        case is URL.Type:
            return (userDefaults.url(forKey: key) as! T)
        case is Array<String>.Type:
            return (userDefaults.stringArray(forKey: key) as! T)
        case is Array<Any>.Type:
            return (userDefaults.array(forKey: key) as! T)
        default:
            fatalError("Unsupported UserDefault type \(T.self)")
            // cachedValue = (userDefaults.object(forKey: key) as! T)
        }
    }
}

//public class AtomicUserDefault<T>: UserDefault<T> {
//    private let atomicCachedValue: AtomicWrapper<T?> = AtomicWrapper(value: nil)
//    
//    public override var wrappedValue: T {
//        get {
//            return atomicCachedValue.modify({ value in
//                if let strongValue = value {
//                    return strongValue
//                }
//                return self.readFromUserDefaults()
//            })!
//        }
//        set {
//            let _ = atomicCachedValue.modify({ _ in
//                userDefaults.set(newValue, forKey: key)
//                return newValue
//            })
//        }
//    }
//}



//  Based on ConcurrentDictionary.swift from https://github.com/peterprokop/SwiftConcurrentCollections

/// Thread-safe UserDefaults dictionary wrapper
/// - Important: Note that this is a `class`, i.e. reference (not value) type
/// - Important: Key can only be String type
public class UserDefaultsBackedDictionary<Key: Hashable, Value> {
    public let userDefaultsKey: String
    public let userDefaults: UserDefaults
        
    private var container: [Key: Value]? = nil
    private let rwlock = RWLock()
    private let threadSafe: Bool

    public var keys: [Key] {
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "KEYS")
        #endif
        let result: [Key]
        if threadSafe {
            rwlock.readLock()
        }
        if container == nil {
            container = userDefaultsContainer
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "EXTRACTED: \(container!)")
            #endif
        } else {
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "FROM CACHE: \(container!)")
            #endif
        }
        result = Array(container!.keys)
        if threadSafe {
            rwlock.unlock()
        }
        return result
    }

    public var values: [Value] {
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "VALUES")
        #endif
        let result: [Value]
        if threadSafe {
            rwlock.readLock()
        }
        if container == nil {
            container = userDefaultsContainer
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "EXTRACTED: \(container!)")
            #endif
        } else {
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "FROM CACHE: \(container!)")
            #endif
        }
        result = Array(container!.values)
        if threadSafe {
            rwlock.unlock()
        }
        return result
    }
    
    public init(userDefaultsKey: String, userDefaults: UserDefaults = .standard, threadSafe: Bool) {
        self.userDefaultsKey = userDefaultsKey
        self.userDefaults = userDefaults
        self.threadSafe = threadSafe
    }

    /// Sets the value for key
    ///
    /// - Parameters:
    ///   - value: The value to set for key
    ///   - key: The key to set value for
    public func set(value: Value, forKey key: Key) {
        if threadSafe {
            rwlock.writeLock()
        }
        _set(value: value, forKey: key)
        if threadSafe {
            rwlock.unlock()
        }
    }

    @discardableResult
    public func remove(_ key: Key) -> Value? {
        let result: Value?
        if threadSafe {
            rwlock.writeLock()
        }
        result = _remove(key)
        if threadSafe {
            rwlock.unlock()
        }
        return result
    }
    
    @discardableResult
    public func removeValue(forKey: Key) -> Value? {
        return self.remove(forKey)
    }

    public func contains(_ key: Key) -> Bool {
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "CONTAINS")
        #endif
        let result: Bool
        if threadSafe {
            rwlock.readLock()
        }
        if container == nil {
            container = userDefaultsContainer
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "EXTRACTED: \(container!)")
            #endif
        } else {
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "FROM CACHE: \(container!)")
            #endif
        }
        result = container!.index(forKey: key) != nil
        if threadSafe {
            rwlock.unlock()
        }
        return result
    }

    public func value(forKey key: Key) -> Value? {
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "VALUE")
        #endif
        let result: Value?
        if threadSafe {
            rwlock.readLock()
        }
        if container == nil {
            container = userDefaultsContainer
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "EXTRACTED: \(container!)")
            #endif
        } else {
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "FROM CACHE: \(container!)")
            #endif
        }
        result = container![key]
        if threadSafe {
            rwlock.unlock()
        }
        return result
    }

    public func mutateValue(forKey key: Key, mutation: (Value) -> Value) {
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "MUTATE")
        #endif
        if threadSafe {
            rwlock.writeLock()
        }
        if container == nil {
            container = userDefaultsContainer
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "EXTRACTED: \(container!)")
            #endif
        } else {
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "FROM CACHE: \(container!)")
            #endif
        }
        if let value = container![key] {
            container![key] = mutation(value)
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "UPDATING CACHE \(key): \(value), \(container!)")
            #endif
            userDefaultsContainer = container!
            #if DEBUG
            SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "CACHE UPDATED \(key): \(value), \(container!)")
            #endif
        }
        if threadSafe {
            rwlock.unlock()
        }
    }
    
    public var isEmpty: Bool {
        return self.keys.isEmpty
    }

    // MARK: Subscript
    public subscript(key: Key) -> Value? {
        get {
            return value(forKey: key)
        }
        set {
            if threadSafe {
                rwlock.writeLock()
            }
            defer {
                if threadSafe {
                    rwlock.unlock()
                }
            }
            guard let newValue = newValue else {
                _remove(key)
                return
            }
            _set(value: newValue, forKey: key)
        }
    }

    // MARK: Private
    @inline(__always)
    private func _set(value: Value, forKey key: Key) {
        if container == nil {
            container = userDefaultsContainer
        }
        self.container![key] = value
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "UPDATING CACHE \(key): \(value), \(container!)")
        #endif
        userDefaultsContainer = container!
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "CACHE UPDATED \(key): \(value), \(container!)")
        #endif
    }

    @inline(__always)
    @discardableResult
    private func _remove(_ key: Key) -> Value? {
        if container == nil {
            container = userDefaultsContainer
        }
        guard let index = container!.index(forKey: key) else { return nil }

        let tuple = container!.remove(at: index)
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "UPDATING CACHE REMOVE \(key) \(container!)")
        #endif
        userDefaultsContainer = container!
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "CACHE UPDATED REMOVED \(key) \(container!)")
        #endif
        return tuple.value
    }
    
    private var userDefaultsContainer: [Key: Value] {
        get {
            return userDefaults.dictionary(forKey: userDefaultsKey) as! [Key: Value]
        }
        set {
            userDefaults.set(newValue, forKey: userDefaultsKey)
        }
    }
    
    public func drop() {
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "DROPPING")
        #endif
        if threadSafe {
            rwlock.writeLock()
        }
        userDefaults.removeObject(forKey: userDefaultsKey)
        container = userDefaultsContainer
        #if DEBUG
        SGtrace("UD.\(userDefaultsKey)\(threadSafe ? "-ts" : "")", what: "DROPPED: \(container!)")
        #endif
        if threadSafe {
            rwlock.unlock()
        }
    }

}


#if DEBUG
private let queue = DispatchQueue(label: "app.swiftgram.ios.trace", qos: .utility)

public func SGtrace(_ domain: String, what: @autoclosure() -> String) {
    let string = what()
    var rawTime = time_t()
    time(&rawTime)
    var timeinfo = tm()
    localtime_r(&rawTime, &timeinfo)
    
    var curTime = timeval()
    gettimeofday(&curTime, nil)
    let seconds = Int(curTime.tv_sec % 60)  // Extracting the current second
    let microseconds = curTime.tv_usec  // Full microsecond precision

    queue.async {
        let result = String(format: "[%@] %d-%d-%d %02d:%02d:%02d.%06d %@", arguments: [domain, Int(timeinfo.tm_year) + 1900, Int(timeinfo.tm_mon + 1), Int(timeinfo.tm_mday), Int(timeinfo.tm_hour), Int(timeinfo.tm_min), seconds, microseconds, string])
        
        print(result)
    }
}
#endif
