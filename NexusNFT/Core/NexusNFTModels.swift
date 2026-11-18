import Foundation

/// Local presentation model. It does not change Telegram's server-side gift ownership.
public struct NexusNFTGift: Codable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var collection: String
    public var artworkResource: String?
    public var level: Int
    public var experience: Int
    public var isWorn: Bool
    public var isVisible: Bool
    public var sortIndex: Int
    public var attributes: [NexusNFTAttribute]

    public init(id: UUID = UUID(), title: String, collection: String, artworkResource: String? = nil,
                level: Int = 1, experience: Int = 0, isWorn: Bool = false, isVisible: Bool = true,
                sortIndex: Int = 0, attributes: [NexusNFTAttribute] = []) {
        self.id = id
        self.title = title
        self.collection = collection
        self.artworkResource = artworkResource
        self.level = max(1, level)
        self.experience = max(0, experience)
        self.isWorn = isWorn
        self.isVisible = isVisible
        self.sortIndex = sortIndex
        self.attributes = attributes
    }
}

public struct NexusNFTAttribute: Codable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var value: String
    public var rarity: String

    public init(name: String, value: String, rarity: String = "Common") {
        self.name = name
        self.value = value
        self.rarity = rarity
    }
}

public struct NexusNFTWallet: Codable, Equatable {
    /// App-local progression points; never represents Telegram Stars or money.
    public var upgradePoints: Int
    public init(upgradePoints: Int = 0) { self.upgradePoints = max(0, upgradePoints) }
}

public enum NexusNFTUpgradeError: Error, Equatable {
    case giftNotFound
    case maximumLevel
    case insufficientPoints(required: Int, available: Int)
}
