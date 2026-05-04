import Postbox

public typealias EngineMemoryBuffer = MemoryBuffer
public typealias EnginePostboxDecoder = PostboxDecoder
public typealias EnginePostboxEncoder = PostboxEncoder
public typealias EngineAdaptedPostboxDecoder = AdaptedPostboxDecoder
public typealias EngineItemCollectionId = ItemCollectionId
public typealias EngineStoryId = StoryId
public typealias EngineFetchResourceSourceType = FetchResourceSourceType
public typealias EngineFetchResourceError = FetchResourceError
public typealias EngineCodableEntry = CodableEntry
public typealias EngineNoticeEntryKey = NoticeEntryKey
public typealias EngineChatListIndex = ChatListIndex
public typealias EngineTempBoxFile = TempBoxFile
public typealias EngineItemCollectionItemIndex = ItemCollectionItemIndex
public typealias EngineItemCollectionViewEntryIndex = ItemCollectionViewEntryIndex
public typealias EngineValueBoxEncryptionParameters = ValueBoxEncryptionParameters
public typealias EngineMessageAndThreadId = MessageAndThreadId
public typealias EnginePeerStoryStats = PeerStoryStats
public typealias EngineMessageHistoryAnchorIndex = MessageHistoryAnchorIndex
public typealias EngineChatListTotalUnreadStateCategory = ChatListTotalUnreadStateCategory
public typealias EngineChatListTotalUnreadStateStats = ChatListTotalUnreadStateStats
public typealias EngineChatListTotalUnreadState = ChatListTotalUnreadState
public typealias EngineItemCacheEntryId = ItemCacheEntryId
public typealias EnginePeerSummaryCounterTags = PeerSummaryCounterTags
public typealias EngineHashFunctions = HashFunctions
public typealias EngineCachedMediaResourceRepresentationResult = CachedMediaResourceRepresentationResult
public typealias EngineMediaResourceDataFetchResult = MediaResourceDataFetchResult
public typealias EngineMediaResourceDataFetchError = MediaResourceDataFetchError
public typealias EngineMediaResourceStatus = MediaResourceStatus
public typealias EngineCachedPeerData = CachedPeerData

public func engineFileSize(_ path: String, useTotalFileAllocatedSize: Bool = false) -> Int64? {
    return fileSize(path, useTotalFileAllocatedSize: useTotalFileAllocatedSize)
}
