public extension Api {
    enum PremiumSubscriptionOption: TypeConstructorDescription {
        public class Cons_premiumSubscriptionOption: TypeConstructorDescription {
            public var flags: Int32
            public var transaction: String?
            public var months: Int32
            public var currency: String
            public var amount: Int64
            public var botUrl: String
            public var storeProduct: String?
            public init(flags: Int32, transaction: String?, months: Int32, currency: String, amount: Int64, botUrl: String, storeProduct: String?) {
                self.flags = flags
                self.transaction = transaction
                self.months = months
                self.currency = currency
                self.amount = amount
                self.botUrl = botUrl
                self.storeProduct = storeProduct
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("premiumSubscriptionOption", [("flags", ConstructorParameterDescription(self.flags)), ("transaction", ConstructorParameterDescription(self.transaction)), ("months", ConstructorParameterDescription(self.months)), ("currency", ConstructorParameterDescription(self.currency)), ("amount", ConstructorParameterDescription(self.amount)), ("botUrl", ConstructorParameterDescription(self.botUrl)), ("storeProduct", ConstructorParameterDescription(self.storeProduct))])
            }
        }
        case premiumSubscriptionOption(Cons_premiumSubscriptionOption)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .premiumSubscriptionOption(let _data):
                if boxed {
                    buffer.appendInt32(1596792306)
                }
                serializeInt32(_data.flags, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 3) != 0 {
                    serializeString(_data.transaction!, buffer: buffer, boxed: false)
                }
                serializeInt32(_data.months, buffer: buffer, boxed: false)
                serializeString(_data.currency, buffer: buffer, boxed: false)
                serializeInt64(_data.amount, buffer: buffer, boxed: false)
                serializeString(_data.botUrl, buffer: buffer, boxed: false)
                if Int(_data.flags) & Int(1 << 0) != 0 {
                    serializeString(_data.storeProduct!, buffer: buffer, boxed: false)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .premiumSubscriptionOption(let _data):
                return ("premiumSubscriptionOption", [("flags", ConstructorParameterDescription(_data.flags)), ("transaction", ConstructorParameterDescription(_data.transaction)), ("months", ConstructorParameterDescription(_data.months)), ("currency", ConstructorParameterDescription(_data.currency)), ("amount", ConstructorParameterDescription(_data.amount)), ("botUrl", ConstructorParameterDescription(_data.botUrl)), ("storeProduct", ConstructorParameterDescription(_data.storeProduct))])
            }
        }

        public static func parse_premiumSubscriptionOption(_ reader: BufferReader) -> PremiumSubscriptionOption? {
            var _1: Int32?
            _1 = reader.readInt32()
            var _2: String?
            if Int(_1!) & Int(1 << 3) != 0 {
                _2 = parseString(reader)
            }
            var _3: Int32?
            _3 = reader.readInt32()
            var _4: String?
            _4 = parseString(reader)
            var _5: Int64?
            _5 = reader.readInt64()
            var _6: String?
            _6 = parseString(reader)
            var _7: String?
            if Int(_1!) & Int(1 << 0) != 0 {
                _7 = parseString(reader)
            }
            let _c1 = _1 != nil
            let _c2 = (Int(_1!) & Int(1 << 3) == 0) || _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            let _c6 = _6 != nil
            let _c7 = (Int(_1!) & Int(1 << 0) == 0) || _7 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 && _c6 && _c7 {
                return Api.PremiumSubscriptionOption.premiumSubscriptionOption(Cons_premiumSubscriptionOption(flags: _1!, transaction: _2, months: _3!, currency: _4!, amount: _5!, botUrl: _6!, storeProduct: _7))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum PrepaidGiveaway: TypeConstructorDescription {
        public class Cons_prepaidGiveaway: TypeConstructorDescription {
            public var id: Int64
            public var months: Int32
            public var quantity: Int32
            public var date: Int32
            public init(id: Int64, months: Int32, quantity: Int32, date: Int32) {
                self.id = id
                self.months = months
                self.quantity = quantity
                self.date = date
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("prepaidGiveaway", [("id", ConstructorParameterDescription(self.id)), ("months", ConstructorParameterDescription(self.months)), ("quantity", ConstructorParameterDescription(self.quantity)), ("date", ConstructorParameterDescription(self.date))])
            }
        }
        public class Cons_prepaidStarsGiveaway: TypeConstructorDescription {
            public var id: Int64
            public var stars: Int64
            public var quantity: Int32
            public var boosts: Int32
            public var date: Int32
            public init(id: Int64, stars: Int64, quantity: Int32, boosts: Int32, date: Int32) {
                self.id = id
                self.stars = stars
                self.quantity = quantity
                self.boosts = boosts
                self.date = date
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("prepaidStarsGiveaway", [("id", ConstructorParameterDescription(self.id)), ("stars", ConstructorParameterDescription(self.stars)), ("quantity", ConstructorParameterDescription(self.quantity)), ("boosts", ConstructorParameterDescription(self.boosts)), ("date", ConstructorParameterDescription(self.date))])
            }
        }
        case prepaidGiveaway(Cons_prepaidGiveaway)
        case prepaidStarsGiveaway(Cons_prepaidStarsGiveaway)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .prepaidGiveaway(let _data):
                if boxed {
                    buffer.appendInt32(-1303143084)
                }
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt32(_data.months, buffer: buffer, boxed: false)
                serializeInt32(_data.quantity, buffer: buffer, boxed: false)
                serializeInt32(_data.date, buffer: buffer, boxed: false)
                break
            case .prepaidStarsGiveaway(let _data):
                if boxed {
                    buffer.appendInt32(-1700956192)
                }
                serializeInt64(_data.id, buffer: buffer, boxed: false)
                serializeInt64(_data.stars, buffer: buffer, boxed: false)
                serializeInt32(_data.quantity, buffer: buffer, boxed: false)
                serializeInt32(_data.boosts, buffer: buffer, boxed: false)
                serializeInt32(_data.date, buffer: buffer, boxed: false)
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .prepaidGiveaway(let _data):
                return ("prepaidGiveaway", [("id", ConstructorParameterDescription(_data.id)), ("months", ConstructorParameterDescription(_data.months)), ("quantity", ConstructorParameterDescription(_data.quantity)), ("date", ConstructorParameterDescription(_data.date))])
            case .prepaidStarsGiveaway(let _data):
                return ("prepaidStarsGiveaway", [("id", ConstructorParameterDescription(_data.id)), ("stars", ConstructorParameterDescription(_data.stars)), ("quantity", ConstructorParameterDescription(_data.quantity)), ("boosts", ConstructorParameterDescription(_data.boosts)), ("date", ConstructorParameterDescription(_data.date))])
            }
        }

        public static func parse_prepaidGiveaway(_ reader: BufferReader) -> PrepaidGiveaway? {
            var _1: Int64?
            _1 = reader.readInt64()
            var _2: Int32?
            _2 = reader.readInt32()
            var _3: Int32?
            _3 = reader.readInt32()
            var _4: Int32?
            _4 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            if _c1 && _c2 && _c3 && _c4 {
                return Api.PrepaidGiveaway.prepaidGiveaway(Cons_prepaidGiveaway(id: _1!, months: _2!, quantity: _3!, date: _4!))
            }
            else {
                return nil
            }
        }
        public static func parse_prepaidStarsGiveaway(_ reader: BufferReader) -> PrepaidGiveaway? {
            var _1: Int64?
            _1 = reader.readInt64()
            var _2: Int64?
            _2 = reader.readInt64()
            var _3: Int32?
            _3 = reader.readInt32()
            var _4: Int32?
            _4 = reader.readInt32()
            var _5: Int32?
            _5 = reader.readInt32()
            let _c1 = _1 != nil
            let _c2 = _2 != nil
            let _c3 = _3 != nil
            let _c4 = _4 != nil
            let _c5 = _5 != nil
            if _c1 && _c2 && _c3 && _c4 && _c5 {
                return Api.PrepaidGiveaway.prepaidStarsGiveaway(Cons_prepaidStarsGiveaway(id: _1!, stars: _2!, quantity: _3!, boosts: _4!, date: _5!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum PrivacyKey: TypeConstructorDescription {
        case privacyKeyAbout
        case privacyKeyAddedByPhone
        case privacyKeyBirthday
        case privacyKeyChatInvite
        case privacyKeyForwards
        case privacyKeyNoPaidMessages
        case privacyKeyPhoneCall
        case privacyKeyPhoneNumber
        case privacyKeyPhoneP2P
        case privacyKeyProfilePhoto
        case privacyKeySavedMusic
        case privacyKeyStarGiftsAutoSave
        case privacyKeyStatusTimestamp
        case privacyKeyVoiceMessages

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .privacyKeyAbout:
                if boxed {
                    buffer.appendInt32(-1534675103)
                }
                break
            case .privacyKeyAddedByPhone:
                if boxed {
                    buffer.appendInt32(1124062251)
                }
                break
            case .privacyKeyBirthday:
                if boxed {
                    buffer.appendInt32(536913176)
                }
                break
            case .privacyKeyChatInvite:
                if boxed {
                    buffer.appendInt32(1343122938)
                }
                break
            case .privacyKeyForwards:
                if boxed {
                    buffer.appendInt32(1777096355)
                }
                break
            case .privacyKeyNoPaidMessages:
                if boxed {
                    buffer.appendInt32(399722706)
                }
                break
            case .privacyKeyPhoneCall:
                if boxed {
                    buffer.appendInt32(1030105979)
                }
                break
            case .privacyKeyPhoneNumber:
                if boxed {
                    buffer.appendInt32(-778378131)
                }
                break
            case .privacyKeyPhoneP2P:
                if boxed {
                    buffer.appendInt32(961092808)
                }
                break
            case .privacyKeyProfilePhoto:
                if boxed {
                    buffer.appendInt32(-1777000467)
                }
                break
            case .privacyKeySavedMusic:
                if boxed {
                    buffer.appendInt32(-8759525)
                }
                break
            case .privacyKeyStarGiftsAutoSave:
                if boxed {
                    buffer.appendInt32(749010424)
                }
                break
            case .privacyKeyStatusTimestamp:
                if boxed {
                    buffer.appendInt32(-1137792208)
                }
                break
            case .privacyKeyVoiceMessages:
                if boxed {
                    buffer.appendInt32(110621716)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .privacyKeyAbout:
                return ("privacyKeyAbout", [])
            case .privacyKeyAddedByPhone:
                return ("privacyKeyAddedByPhone", [])
            case .privacyKeyBirthday:
                return ("privacyKeyBirthday", [])
            case .privacyKeyChatInvite:
                return ("privacyKeyChatInvite", [])
            case .privacyKeyForwards:
                return ("privacyKeyForwards", [])
            case .privacyKeyNoPaidMessages:
                return ("privacyKeyNoPaidMessages", [])
            case .privacyKeyPhoneCall:
                return ("privacyKeyPhoneCall", [])
            case .privacyKeyPhoneNumber:
                return ("privacyKeyPhoneNumber", [])
            case .privacyKeyPhoneP2P:
                return ("privacyKeyPhoneP2P", [])
            case .privacyKeyProfilePhoto:
                return ("privacyKeyProfilePhoto", [])
            case .privacyKeySavedMusic:
                return ("privacyKeySavedMusic", [])
            case .privacyKeyStarGiftsAutoSave:
                return ("privacyKeyStarGiftsAutoSave", [])
            case .privacyKeyStatusTimestamp:
                return ("privacyKeyStatusTimestamp", [])
            case .privacyKeyVoiceMessages:
                return ("privacyKeyVoiceMessages", [])
            }
        }

        public static func parse_privacyKeyAbout(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeyAbout
        }
        public static func parse_privacyKeyAddedByPhone(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeyAddedByPhone
        }
        public static func parse_privacyKeyBirthday(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeyBirthday
        }
        public static func parse_privacyKeyChatInvite(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeyChatInvite
        }
        public static func parse_privacyKeyForwards(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeyForwards
        }
        public static func parse_privacyKeyNoPaidMessages(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeyNoPaidMessages
        }
        public static func parse_privacyKeyPhoneCall(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeyPhoneCall
        }
        public static func parse_privacyKeyPhoneNumber(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeyPhoneNumber
        }
        public static func parse_privacyKeyPhoneP2P(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeyPhoneP2P
        }
        public static func parse_privacyKeyProfilePhoto(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeyProfilePhoto
        }
        public static func parse_privacyKeySavedMusic(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeySavedMusic
        }
        public static func parse_privacyKeyStarGiftsAutoSave(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeyStarGiftsAutoSave
        }
        public static func parse_privacyKeyStatusTimestamp(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeyStatusTimestamp
        }
        public static func parse_privacyKeyVoiceMessages(_ reader: BufferReader) -> PrivacyKey? {
            return Api.PrivacyKey.privacyKeyVoiceMessages
        }
    }
}
public extension Api {
    enum PrivacyRule: TypeConstructorDescription {
        public class Cons_privacyValueAllowChatParticipants: TypeConstructorDescription {
            public var chats: [Int64]
            public init(chats: [Int64]) {
                self.chats = chats
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("privacyValueAllowChatParticipants", [("chats", ConstructorParameterDescription(self.chats))])
            }
        }
        public class Cons_privacyValueAllowUsers: TypeConstructorDescription {
            public var users: [Int64]
            public init(users: [Int64]) {
                self.users = users
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("privacyValueAllowUsers", [("users", ConstructorParameterDescription(self.users))])
            }
        }
        public class Cons_privacyValueDisallowChatParticipants: TypeConstructorDescription {
            public var chats: [Int64]
            public init(chats: [Int64]) {
                self.chats = chats
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("privacyValueDisallowChatParticipants", [("chats", ConstructorParameterDescription(self.chats))])
            }
        }
        public class Cons_privacyValueDisallowUsers: TypeConstructorDescription {
            public var users: [Int64]
            public init(users: [Int64]) {
                self.users = users
            }
            public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
                return ("privacyValueDisallowUsers", [("users", ConstructorParameterDescription(self.users))])
            }
        }
        case privacyValueAllowAll
        case privacyValueAllowBots
        case privacyValueAllowChatParticipants(Cons_privacyValueAllowChatParticipants)
        case privacyValueAllowCloseFriends
        case privacyValueAllowContacts
        case privacyValueAllowPremium
        case privacyValueAllowUsers(Cons_privacyValueAllowUsers)
        case privacyValueDisallowAll
        case privacyValueDisallowBots
        case privacyValueDisallowChatParticipants(Cons_privacyValueDisallowChatParticipants)
        case privacyValueDisallowContacts
        case privacyValueDisallowUsers(Cons_privacyValueDisallowUsers)

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .privacyValueAllowAll:
                if boxed {
                    buffer.appendInt32(1698855810)
                }
                break
            case .privacyValueAllowBots:
                if boxed {
                    buffer.appendInt32(558242653)
                }
                break
            case .privacyValueAllowChatParticipants(let _data):
                if boxed {
                    buffer.appendInt32(1796427406)
                }
                buffer.appendInt32(481674261)
                buffer.appendInt32(Int32(_data.chats.count))
                for item in _data.chats {
                    serializeInt64(item, buffer: buffer, boxed: false)
                }
                break
            case .privacyValueAllowCloseFriends:
                if boxed {
                    buffer.appendInt32(-135735141)
                }
                break
            case .privacyValueAllowContacts:
                if boxed {
                    buffer.appendInt32(-123988)
                }
                break
            case .privacyValueAllowPremium:
                if boxed {
                    buffer.appendInt32(-320241333)
                }
                break
            case .privacyValueAllowUsers(let _data):
                if boxed {
                    buffer.appendInt32(-1198497870)
                }
                buffer.appendInt32(481674261)
                buffer.appendInt32(Int32(_data.users.count))
                for item in _data.users {
                    serializeInt64(item, buffer: buffer, boxed: false)
                }
                break
            case .privacyValueDisallowAll:
                if boxed {
                    buffer.appendInt32(-1955338397)
                }
                break
            case .privacyValueDisallowBots:
                if boxed {
                    buffer.appendInt32(-156895185)
                }
                break
            case .privacyValueDisallowChatParticipants(let _data):
                if boxed {
                    buffer.appendInt32(1103656293)
                }
                buffer.appendInt32(481674261)
                buffer.appendInt32(Int32(_data.chats.count))
                for item in _data.chats {
                    serializeInt64(item, buffer: buffer, boxed: false)
                }
                break
            case .privacyValueDisallowContacts:
                if boxed {
                    buffer.appendInt32(-125240806)
                }
                break
            case .privacyValueDisallowUsers(let _data):
                if boxed {
                    buffer.appendInt32(-463335103)
                }
                buffer.appendInt32(481674261)
                buffer.appendInt32(Int32(_data.users.count))
                for item in _data.users {
                    serializeInt64(item, buffer: buffer, boxed: false)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .privacyValueAllowAll:
                return ("privacyValueAllowAll", [])
            case .privacyValueAllowBots:
                return ("privacyValueAllowBots", [])
            case .privacyValueAllowChatParticipants(let _data):
                return ("privacyValueAllowChatParticipants", [("chats", ConstructorParameterDescription(_data.chats))])
            case .privacyValueAllowCloseFriends:
                return ("privacyValueAllowCloseFriends", [])
            case .privacyValueAllowContacts:
                return ("privacyValueAllowContacts", [])
            case .privacyValueAllowPremium:
                return ("privacyValueAllowPremium", [])
            case .privacyValueAllowUsers(let _data):
                return ("privacyValueAllowUsers", [("users", ConstructorParameterDescription(_data.users))])
            case .privacyValueDisallowAll:
                return ("privacyValueDisallowAll", [])
            case .privacyValueDisallowBots:
                return ("privacyValueDisallowBots", [])
            case .privacyValueDisallowChatParticipants(let _data):
                return ("privacyValueDisallowChatParticipants", [("chats", ConstructorParameterDescription(_data.chats))])
            case .privacyValueDisallowContacts:
                return ("privacyValueDisallowContacts", [])
            case .privacyValueDisallowUsers(let _data):
                return ("privacyValueDisallowUsers", [("users", ConstructorParameterDescription(_data.users))])
            }
        }

        public static func parse_privacyValueAllowAll(_ reader: BufferReader) -> PrivacyRule? {
            return Api.PrivacyRule.privacyValueAllowAll
        }
        public static func parse_privacyValueAllowBots(_ reader: BufferReader) -> PrivacyRule? {
            return Api.PrivacyRule.privacyValueAllowBots
        }
        public static func parse_privacyValueAllowChatParticipants(_ reader: BufferReader) -> PrivacyRule? {
            var _1: [Int64]?
            if let _ = reader.readInt32() {
                _1 = Api.parseVector(reader, elementSignature: 570911930, elementType: Int64.self)
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.PrivacyRule.privacyValueAllowChatParticipants(Cons_privacyValueAllowChatParticipants(chats: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_privacyValueAllowCloseFriends(_ reader: BufferReader) -> PrivacyRule? {
            return Api.PrivacyRule.privacyValueAllowCloseFriends
        }
        public static func parse_privacyValueAllowContacts(_ reader: BufferReader) -> PrivacyRule? {
            return Api.PrivacyRule.privacyValueAllowContacts
        }
        public static func parse_privacyValueAllowPremium(_ reader: BufferReader) -> PrivacyRule? {
            return Api.PrivacyRule.privacyValueAllowPremium
        }
        public static func parse_privacyValueAllowUsers(_ reader: BufferReader) -> PrivacyRule? {
            var _1: [Int64]?
            if let _ = reader.readInt32() {
                _1 = Api.parseVector(reader, elementSignature: 570911930, elementType: Int64.self)
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.PrivacyRule.privacyValueAllowUsers(Cons_privacyValueAllowUsers(users: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_privacyValueDisallowAll(_ reader: BufferReader) -> PrivacyRule? {
            return Api.PrivacyRule.privacyValueDisallowAll
        }
        public static func parse_privacyValueDisallowBots(_ reader: BufferReader) -> PrivacyRule? {
            return Api.PrivacyRule.privacyValueDisallowBots
        }
        public static func parse_privacyValueDisallowChatParticipants(_ reader: BufferReader) -> PrivacyRule? {
            var _1: [Int64]?
            if let _ = reader.readInt32() {
                _1 = Api.parseVector(reader, elementSignature: 570911930, elementType: Int64.self)
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.PrivacyRule.privacyValueDisallowChatParticipants(Cons_privacyValueDisallowChatParticipants(chats: _1!))
            }
            else {
                return nil
            }
        }
        public static func parse_privacyValueDisallowContacts(_ reader: BufferReader) -> PrivacyRule? {
            return Api.PrivacyRule.privacyValueDisallowContacts
        }
        public static func parse_privacyValueDisallowUsers(_ reader: BufferReader) -> PrivacyRule? {
            var _1: [Int64]?
            if let _ = reader.readInt32() {
                _1 = Api.parseVector(reader, elementSignature: 570911930, elementType: Int64.self)
            }
            let _c1 = _1 != nil
            if _c1 {
                return Api.PrivacyRule.privacyValueDisallowUsers(Cons_privacyValueDisallowUsers(users: _1!))
            }
            else {
                return nil
            }
        }
    }
}
public extension Api {
    enum ProfileTab: TypeConstructorDescription {
        case profileTabFiles
        case profileTabGifs
        case profileTabGifts
        case profileTabLinks
        case profileTabMedia
        case profileTabMusic
        case profileTabPosts
        case profileTabVoice

        public func serialize(_ buffer: Buffer, _ boxed: Swift.Bool) {
            switch self {
            case .profileTabFiles:
                if boxed {
                    buffer.appendInt32(-1422681088)
                }
                break
            case .profileTabGifs:
                if boxed {
                    buffer.appendInt32(-1564412267)
                }
                break
            case .profileTabGifts:
                if boxed {
                    buffer.appendInt32(1296815210)
                }
                break
            case .profileTabLinks:
                if boxed {
                    buffer.appendInt32(-748329831)
                }
                break
            case .profileTabMedia:
                if boxed {
                    buffer.appendInt32(1925597525)
                }
                break
            case .profileTabMusic:
                if boxed {
                    buffer.appendInt32(-1624780178)
                }
                break
            case .profileTabPosts:
                if boxed {
                    buffer.appendInt32(-1181952362)
                }
                break
            case .profileTabVoice:
                if boxed {
                    buffer.appendInt32(-461960914)
                }
                break
            }
        }

        public func descriptionFields() -> (String, [(String, ConstructorParameterDescription)]) {
            switch self {
            case .profileTabFiles:
                return ("profileTabFiles", [])
            case .profileTabGifs:
                return ("profileTabGifs", [])
            case .profileTabGifts:
                return ("profileTabGifts", [])
            case .profileTabLinks:
                return ("profileTabLinks", [])
            case .profileTabMedia:
                return ("profileTabMedia", [])
            case .profileTabMusic:
                return ("profileTabMusic", [])
            case .profileTabPosts:
                return ("profileTabPosts", [])
            case .profileTabVoice:
                return ("profileTabVoice", [])
            }
        }

        public static func parse_profileTabFiles(_ reader: BufferReader) -> ProfileTab? {
            return Api.ProfileTab.profileTabFiles
        }
        public static func parse_profileTabGifs(_ reader: BufferReader) -> ProfileTab? {
            return Api.ProfileTab.profileTabGifs
        }
        public static func parse_profileTabGifts(_ reader: BufferReader) -> ProfileTab? {
            return Api.ProfileTab.profileTabGifts
        }
        public static func parse_profileTabLinks(_ reader: BufferReader) -> ProfileTab? {
            return Api.ProfileTab.profileTabLinks
        }
        public static func parse_profileTabMedia(_ reader: BufferReader) -> ProfileTab? {
            return Api.ProfileTab.profileTabMedia
        }
        public static func parse_profileTabMusic(_ reader: BufferReader) -> ProfileTab? {
            return Api.ProfileTab.profileTabMusic
        }
        public static func parse_profileTabPosts(_ reader: BufferReader) -> ProfileTab? {
            return Api.ProfileTab.profileTabPosts
        }
        public static func parse_profileTabVoice(_ reader: BufferReader) -> ProfileTab? {
            return Api.ProfileTab.profileTabVoice
        }
    }
}
