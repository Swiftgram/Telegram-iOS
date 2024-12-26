import Foundation

public func transformValue<T, E, R>(_ f: @escaping(T) -> R) -> (Signal<T, E>) -> Signal<R, E> {
    return map(f)
}

public func transformValueToSignal<T, R, E>(_ f: @escaping(T) -> Signal<R, E>) -> (Signal<T, E>) -> Signal<R, E> {
    return mapToSignal(f)
}

public func convertSignalWithNoErrorToSignalWithError<T, R, E>(_ f: @escaping(T) -> Signal<R, E>) -> (Signal<T, NoError>) -> Signal<R, E> {
    return mapToSignalPromotingError(f)
}

public func ignoreSignalErrors<T, E>(onError: ((E) -> Void)? = nil) -> (Signal<T, E>) -> Signal<T, NoError> {
    return { signal in
        return signal |> `catch` { error in
            // Log the error using the provided callback, if any
            onError?(error)
            
            // Returning a signal that completes without errors
            return Signal { subscriber in
                subscriber.putCompletion()
                return EmptyDisposable
            }
        }
    }
}