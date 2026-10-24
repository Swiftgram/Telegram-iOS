extension PostboxImpl {
    func sgSearchLocalPeerId(query: String) -> PeerId? {
        var result: PeerId? = nil
        let minus100Prefix = "-100"
        var query = query
        if query.hasPrefix(minus100Prefix) {
            query = String(query.dropFirst(minus100Prefix.count))
        }
        guard let queryInt64 = Int64(query) else { return nil }
        let possiblePeerId = PeerId(queryInt64)


        if self.cachedPeerDataTable.get(possiblePeerId) != nil {
            #if DEBUG
            print("Found peer \(queryInt64) in cachedPeerDataTable")
            #endif
            return possiblePeerId
        }

        if self.peerTable.get(possiblePeerId) != nil {
            #if DEBUG
            print("Found peer \(queryInt64) in peerTable")
            #endif
            return possiblePeerId
        }

        self.valueBox.scanInt64(self.chatListIndexTable.table, keys: { key in
            let peerId = PeerId(key)
            let peerIdInt64 = peerId.id._internalGetInt64Value()
            if queryInt64 == peerIdInt64 /* /* For basic groups */ || abs(queryInt64) == peerIdInt64 */ {
                #if DEBUG
                print("Found peer \(queryInt64) in chatListIndexTable")
                #endif
                result = peerId
                return false
            }
            return true
        })

        return result
    }
}
