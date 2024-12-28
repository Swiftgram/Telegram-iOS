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

extension Signal where E: Error {
    @available(iOS 13.0, *)
    public func awaitable() async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            var disposable: Disposable?
            disposable = self.start(
                next: { value in
                    continuation.resume(returning: value)
                    disposable?.dispose()
                },
                error: { error in
                    continuation.resume(throwing: error)
                    disposable?.dispose()
                },
                completed: {
                    disposable?.dispose()
                }
            )
        }
    }
}

extension Signal where E == NoError {
    @available(iOS 13.0, *)
    public func awaitable() async -> T {
        return await withCheckedContinuation { continuation in
            var disposable: Disposable?
            disposable = self.start(
                next: { value in
                    continuation.resume(returning: value)
                    disposable?.dispose()
                },
                error: { _ in
                    // This will never be called for NoError
                    disposable?.dispose()
                },
                completed: {
                    disposable?.dispose()
                }
            )
        }
    }
}

extension Signal {
    @available(iOS 13.0, *)
    public func awaitableStream() -> AsyncStream<T> {
        return AsyncStream { continuation in
            let disposable = self.start(
                next: { value in
                    continuation.yield(value)
                },
                error: { _ in
                    continuation.finish()
                },
                completed: {
                    continuation.finish()
                }
            )
            
            continuation.onTermination = { @Sendable _ in
                disposable.dispose()
            }
        }
    }
}


extension Signal where E == NoError {
    @available(iOS 13.0, *)
    public func awaitableStream() -> AsyncStream<T> {
        return AsyncStream { continuation in
            let disposable = self.start(
                next: { value in
                    continuation.yield(value)
                },
                completed: {
                    continuation.finish()
                }
            )
            
            continuation.onTermination = { @Sendable _ in
                disposable.dispose()
            }
        }
    }
}
