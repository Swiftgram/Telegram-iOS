//// A copy of Atomic from SwiftSignalKit
//import Foundation
//
//public enum AtomicWrapperLockError: Error {
//    case isLocked
//}
//
//public final class AtomicWrapper<T> {
//    private var lock: pthread_mutex_t
//    private var value: T
//    
//    public init(value: T) {
//        self.lock = pthread_mutex_t()
//        self.value = value
//        
//        pthread_mutex_init(&self.lock, nil)
//    }
//    
//    deinit {
//        pthread_mutex_destroy(&self.lock)
//    }
//    
//    public func with<R>(_ f: (T) -> R) -> R {
//        pthread_mutex_lock(&self.lock)
//        let result = f(self.value)
//        pthread_mutex_unlock(&self.lock)
//        
//        return result
//    }
//    
//    public func tryWith<R>(_ f: (T) -> R) throws -> R {
//        if pthread_mutex_trylock(&self.lock) == 0 {
//            let result = f(self.value)
//            pthread_mutex_unlock(&self.lock)
//            return result
//        } else {
//            throw AtomicWrapperLockError.isLocked
//        }
//    }
//    
//    public func modify(_ f: (T) -> T) -> T {
//        pthread_mutex_lock(&self.lock)
//        let result = f(self.value)
//        self.value = result
//        pthread_mutex_unlock(&self.lock)
//        
//        return result
//    }
//    
//    public func swap(_ value: T) -> T {
//        pthread_mutex_lock(&self.lock)
//        let previous = self.value
//        self.value = value
//        pthread_mutex_unlock(&self.lock)
//        
//        return previous
//    }
//}
