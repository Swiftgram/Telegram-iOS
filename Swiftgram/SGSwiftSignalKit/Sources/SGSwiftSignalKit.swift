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

// Wrapper for non-Error types
public struct SignalError<E>: Error {
    public let error: E
    
    public init(_ error: E) {
        self.error = error
    }
}

public struct SignalCompleted: Error {}

// Extension for Signals
// NoError can be marked a
// try? await signal.awaitable()
public extension Signal {
    @available(iOS 13.0, *)
    func awaitable(file: String = #file, line: Int = #line) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            var disposable: Disposable?
            let hasResumed = Atomic<Bool>(value: false)
            disposable = self.start(
                next: { value in
                    if !hasResumed.with({ $0 }) {
                        let _ = hasResumed.swap(true)
                        continuation.resume(returning: value)
                    } else {
                        #if DEBUG
                        // Consider using awaitableStream() or |> take(1)
                        assertionFailure("awaitable Signal emitted more than one value. \(file):\(line)")
                        #endif
                    }
                    disposable?.dispose()
                },
                error: { error in
                    if !hasResumed.with({ $0 }) {
                        let _ = hasResumed.swap(true)
                        if let error = error as? Error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(throwing: SignalError(error))
                        }
                    } else {
                        #if DEBUG
                        // I don't even know what we should consider here. awaitableStream?
                        assertionFailure("awaitable Signal emitted an error after a value. \(file):\(line)")
                        #endif
                    }
                    disposable?.dispose()
                },
                completed: {
                    if !hasResumed.with({ $0 }) {
                        let _ = hasResumed.swap(true)
                        continuation.resume(throwing: SignalCompleted())
                    }
                    disposable?.dispose()
                }
            )
        }
    }

    @available(iOS 13.0, *)
    var task: () async throws -> T {
        {
            let disposable = MetaDisposable()
            return try await withTaskCancellationHandler(operation: {
                return try await withCheckedThrowingContinuation { continuation in
                    disposable.set((self |> take(1)).startStandalone(
                        next: { value in
                            continuation.resume(returning: value)
                        },
                        error: { err in
                            continuation.resume(throwing: SignalError(err))
                        }
                    ))
                }
            }, onCancel: {
                disposable.dispose()
            })
        }
    }
    
    @available(iOS 13.0, *)
    var stream: AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let disposable = self.startStandalone(
                next: { value in
                    continuation.yield(value)
                },
                error: { err in
                    continuation.finish(throwing: SignalError(err))
                },
                completed: {
                    continuation.finish()
                }
            )
            continuation.onTermination = { _ in
                disposable.dispose()
            }
        }
    }
}

@available(iOS 13.0, *)
public extension Signal where E == NoError {
    var task: () async -> T {
        {
            await self.get()
        }
    }

    var stream: AsyncStream<T> {
        AsyncStream { continuation in
            let disposable = self.startStandalone(
                next: { value in
                    continuation.yield(value)
                },
                completed: {
                    continuation.finish()
                }
            )
            continuation.onTermination = { _ in
                disposable.dispose()
            }
        }
    }
}

// Extension for general Signal types - AsyncStream support
public extension Signal {
    @available(iOS 13.0, *)
    func awaitableStream() -> AsyncStream<T> {
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

// Extension for NoError Signal types - AsyncStream support
public extension Signal where E == NoError {
    @available(iOS 13.0, *)
    func awaitableStream() -> AsyncStream<T> {
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
