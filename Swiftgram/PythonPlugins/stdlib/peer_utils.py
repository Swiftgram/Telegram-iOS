"""Conversion between Telegram-iOS `PeerId.toInt64()` and Bot-API style ids.

exteraGram plugins (Android) see users as positive ids, basic groups as `-id` and
channels/supergroups as `-100<id>`. Telegram-iOS packs the namespace into bits 32..34
of the Int64 (see `Postbox/Sources/Peer.swift`): this module converts both ways so
plugins keep working with the ids they know.
"""

NS_USER = 0
NS_GROUP = 1
NS_CHANNEL = 2
NS_SECRET = 3

_CHANNEL_BASE = 1000000000000


def split_packed(packed):
    data = int(packed) & 0xFFFFFFFFFFFFFFFF
    namespace = (data >> 32) & 0x7
    low = data & 0xFFFFFFFF
    high = (data >> 35) & 0xFFFFFFFF
    return namespace, (high << 32) | low


def make_packed(namespace, ident):
    ident = int(ident)
    value = ((ident >> 32) << 35) | (namespace << 32) | (ident & 0xFFFFFFFF)
    if value >= 1 << 63:
        value -= 1 << 64
    return value


def to_plugin_id(packed):
    """Packed iOS peer id -> Bot-API style id (None for secret chats)."""
    namespace, ident = split_packed(packed)
    if namespace == NS_USER:
        return ident
    if namespace == NS_GROUP:
        return -ident
    if namespace == NS_CHANNEL:
        return -(_CHANNEL_BASE + ident)
    return None


def to_packed(peer_id):
    """Bot-API style id -> packed iOS peer id."""
    if isinstance(peer_id, bool) or not isinstance(peer_id, int):
        raise TypeError("peer id must be an int (usernames and titles are not resolved on iOS)")
    if peer_id > 0:
        return make_packed(NS_USER, peer_id)
    if peer_id <= -_CHANNEL_BASE:
        return make_packed(NS_CHANNEL, -peer_id - _CHANNEL_BASE)
    if peer_id < 0:
        return make_packed(NS_GROUP, -peer_id)
    raise ValueError("invalid peer id 0")
