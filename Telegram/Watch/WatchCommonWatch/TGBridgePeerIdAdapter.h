#ifndef Telegraph_TGPeerIdAdapter_h
#define Telegraph_TGPeerIdAdapter_h

#define TG_USER_ID_BITS 52
#define TG_MAX_USER_ID ((int64_t)1 << TG_USER_ID_BITS)

// Using bit shifts to divide the negative space into quarters
// -2^63 (INT64_MIN) divided into 4 parts using shifts
#define TG_GROUP_RANGE_START     ((int64_t)-1)
#define TG_CHANNEL_RANGE_START   (((int64_t)1) << 62)      // -2^62
#define TG_SECRET_CHAT_RANGE_START (((int64_t)1) << 63)    // -2^63 (INT64_MIN)
#define TG_ADMIN_LOG_RANGE_START (-((int64_t)1 << 62) - ((int64_t)1 << 61)) // -2^62 - 2^61

static inline bool TGPeerIdIsUser(int64_t peerId) {
    return peerId > 0 && peerId < TG_MAX_USER_ID;
}

static inline bool TGPeerIdIsGroup(int64_t peerId) {
    return peerId < 0 && peerId > TG_CHANNEL_RANGE_START;
}

static inline bool TGPeerIdIsChannel(int64_t peerId) {
    return peerId <= TG_CHANNEL_RANGE_START && peerId > TG_SECRET_CHAT_RANGE_START;
}

static inline bool TGPeerIdIsSecretChat(int64_t peerId) {
    return peerId <= TG_SECRET_CHAT_RANGE_START && peerId > TG_ADMIN_LOG_RANGE_START;
}

static inline bool TGPeerIdIsAdminLog(int64_t peerId) {
    return peerId <= TG_ADMIN_LOG_RANGE_START && peerId > INT64_MIN;
}

static inline int64_t TGChannelIdFromPeerId(int64_t peerId) {
    if (TGPeerIdIsChannel(peerId)) {
        return TG_CHANNEL_RANGE_START - peerId;
    }
    return 0;
}

static inline int64_t TGPeerIdFromChannelId(int64_t channelId) {
    return TG_CHANNEL_RANGE_START - channelId;
}

static inline int64_t TGPeerIdFromAdminLogId(int64_t channelId) {
    return TG_ADMIN_LOG_RANGE_START - channelId;
}

static inline int64_t TGPeerIdFromGroupId(int64_t groupId) {
    return -groupId;
}

static inline int64_t TGGroupIdFromPeerId(int64_t peerId) {
    if (TGPeerIdIsGroup(peerId)) {
        return -peerId;
    }
    return 0;
}

#endif
