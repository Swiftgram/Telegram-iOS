import Foundation
import Photos
import SwiftSignalKit
import TelegramCore
import AccountContext
import SGSimpleSettings

public var sgOrderedMediaSavingEnabled: Bool {
    return SGSimpleSettings.shared.saveMediaInOrder
}

/// The saves of one batch take turns: a save writes once every save before it has written or ended.
private final class SGCameraRollWriteTurns {
    private let queue = Queue()
    private var next = 0
    private var ended = Set<Int>()
    private var waiting: [Int: () -> Void] = [:]

    /// Calls `start` on the turns' queue when it is `index`'s turn; never if `index` ends first.
    func wait(_ index: Int, start: @escaping () -> Void) {
        self.queue.async {
            if self.next == index {
                start()
            } else if self.next < index {
                self.waiting[index] = start
            }
        }
    }

    func end(_ index: Int) {
        self.queue.async {
            self.ended.insert(index)
            self.waiting.removeValue(forKey: index)
            while self.ended.contains(self.next) {
                self.next += 1
            }
            if let start = self.waiting.removeValue(forKey: self.next) {
                start()
            }
        }
    }
}

/// The saves of several files (an album), in order. Every file downloads at once, and each is written to Photos after
/// the one before it, so the files reach the camera roll in the message's order. Each signal goes up to 0.95 with its
/// download and completes with 1.0 once it is written. Nil when the setting is off or there is one file: the caller
/// then saves as Telegram does.
public func sgOrderedCameraRollSaves(context: AccountContext, items: [(MediaResourceUserLocation, AnyMediaReference)]) -> [Signal<Float, NoError>]? {
    guard sgOrderedMediaSavingEnabled, items.count > 1 else {
        return nil
    }
    let turns = SGCameraRollWriteTurns()
    return items.enumerated().map { index, item in
        let (userLocation, mediaReference) = item
        return Signal<Float, NoError> { subscriber in
            let hasEnded = Atomic<Bool>(value: false)
            let end: () -> Void = {
                if !hasEnded.swap(true) {
                    turns.end(index)
                }
            }
            let download = (fetchMediaData(context: context, userLocation: userLocation, mediaReference: mediaReference)
            |> map { state, _ -> Float in
                if case let .progress(value) = state {
                    return value * 0.95
                }
                return 0.95
            }).start(next: { value in
                subscriber.putNext(value)
            })
            let write = MetaDisposable()
            turns.wait(index, start: {
                // `saveToCameraRoll` completes once Photos has the file; its values can reach 1.0 before that.
                write.set(saveToCameraRoll(context: context, userLocation: userLocation, mediaReference: mediaReference).start(completed: {
                    end()
                    subscriber.putNext(1.0)
                    subscriber.putCompletion()
                }))
            })
            return ActionDisposable {
                download.dispose()
                write.dispose()
                end()
            }
        }
    }
}

private let sgLastCreationDate = Atomic<Date>(value: Date.distantPast)

extension PHAssetChangeRequest {
    /// With the setting on, a saved asset is dated when it is written, not by its file (a video's `creation_time`, a
    /// photo file's EXIF), so it lands at the end of the camera roll. Each date is at least a millisecond after the
    /// previous one, so writes keep their order.
    @discardableResult
    func sgDatedNow() -> Self {
        if sgOrderedMediaSavingEnabled {
            self.creationDate = sgLastCreationDate.modify { max(Date(), $0.addingTimeInterval(0.001)) }
        }
        return self
    }
}
