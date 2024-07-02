#ifndef Telegraph_TGPeerIdAdapter_h
#define Telegraph_TGPeerIdAdapter_h

// Namespace constants based on Swift implementation
#define TG_NAMESPACE_MASK 0x7
#define TG_NAMESPACE_EMPTY 0x0
#define TG_NAMESPACE_CLOUD 0x1
#define TG_NAMESPACE_GROUP 0x2
#define TG_NAMESPACE_CHANNEL 0x3
#define TG_NAMESPACE_SECRET_CHAT 0x4
#define TG_NAMESPACE_ADMIN_LOG 0x5
#define TG_NAMESPACE_AD 0x6
#define TG_NAMESPACE_MAX 0x7

// Helper functions for bit manipulation
static inline uint32_t TGPeerIdGetNamespace(int64_t peerId) {
    uint64_t data = (uint64_t)peerId;
    return (uint32_t)((data >> 32) & TG_NAMESPACE_MASK);
}

static inline int64_t TGPeerIdGetId(int64_t peerId) {
    uint64_t data = (uint64_t)peerId;
    uint64_t idHighBits = (data >> (32 + 3)) << 32;
    uint64_t idLowBits = data & 0xffffffff;
    return (int64_t)(idHighBits | idLowBits);
}

static inline int64_t TGPeerIdMake(uint32_t namespaceId, int64_t id) {
    uint64_t data = 0;
    uint64_t idBits = (uint64_t)id;
    uint64_t idLowBits = idBits & 0xffffffff;
    uint64_t idHighBits = (idBits >> 32) & 0xffffffff;
    
    data |= ((uint64_t)(namespaceId & TG_NAMESPACE_MASK)) << 32;
    data |= (idHighBits << (32 + 3));
    data |= idLowBits;
    
    return (int64_t)data;
}

// Updated peer type checks
static inline bool TGPeerIdIsEmpty(int64_t peerId) {
    return TGPeerIdGetNamespace(peerId) == TG_NAMESPACE_EMPTY;
}

static inline bool TGPeerIdIsUser(int64_t peerId) {
    return TGPeerIdGetNamespace(peerId) == TG_NAMESPACE_CLOUD;
}

static inline bool TGPeerIdIsGroup(int64_t peerId) {
    return TGPeerIdGetNamespace(peerId) == TG_NAMESPACE_GROUP;
}

static inline bool TGPeerIdIsChannel(int64_t peerId) {
    return TGPeerIdGetNamespace(peerId) == TG_NAMESPACE_CHANNEL;
}

static inline bool TGPeerIdIsSecretChat(int64_t peerId) {
    return TGPeerIdGetNamespace(peerId) == TG_NAMESPACE_SECRET_CHAT;
}

static inline bool TGPeerIdIsAdminLog(int64_t peerId) {
    return TGPeerIdGetNamespace(peerId) == TG_NAMESPACE_ADMIN_LOG;
}

static inline bool TGPeerIdIsAd(int64_t peerId) {
    return TGPeerIdGetNamespace(peerId) == TG_NAMESPACE_AD;
}

// Conversion functions
static inline int64_t TGPeerIdFromUserId(int64_t userId) {
    return TGPeerIdMake(TG_NAMESPACE_CLOUD, userId);
}

static inline int64_t TGPeerIdFromGroupId(int64_t groupId) {
    return TGPeerIdMake(TG_NAMESPACE_GROUP, groupId);
}

static inline int64_t TGPeerIdFromChannelId(int64_t channelId) {
    return TGPeerIdMake(TG_NAMESPACE_CHANNEL, channelId);
}

static inline int64_t TGPeerIdFromSecretChatId(int64_t secretChatId) {
    return TGPeerIdMake(TG_NAMESPACE_SECRET_CHAT, secretChatId);
}

static inline int64_t TGPeerIdFromAdminLogId(int64_t adminLogId) {
    return TGPeerIdMake(TG_NAMESPACE_ADMIN_LOG, adminLogId);
}

static inline int64_t TGPeerIdFromAdId(int64_t adId) {
    return TGPeerIdMake(TG_NAMESPACE_AD, adId);
}

// Extract IDs
static inline int64_t TGUserIdFromPeerId(int64_t peerId) {
    return TGPeerIdIsUser(peerId) ? TGPeerIdGetId(peerId) : 0;
}

static inline int64_t TGGroupIdFromPeerId(int64_t peerId) {
    return TGPeerIdIsGroup(peerId) ? TGPeerIdGetId(peerId) : 0;
}

static inline int64_t TGChannelIdFromPeerId(int64_t peerId) {
    return TGPeerIdIsChannel(peerId) ? TGPeerIdGetId(peerId) : 0;
}

static inline int64_t TGSecretChatIdFromPeerId(int64_t peerId) {
    return TGPeerIdIsSecretChat(peerId) ? TGPeerIdGetId(peerId) : 0;
}

static inline int64_t TGAdminLogIdFromPeerId(int64_t peerId) {
    return TGPeerIdIsAdminLog(peerId) ? TGPeerIdGetId(peerId) : 0;
}

static inline int64_t TGAdIdFromPeerId(int64_t peerId) {
    return TGPeerIdIsAd(peerId) ? TGPeerIdGetId(peerId) : 0;
}

#endif
