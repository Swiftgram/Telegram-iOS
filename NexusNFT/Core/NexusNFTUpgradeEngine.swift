import Foundation

public struct NexusNFTUpgradeResult: Equatable {
    public let gift: NexusNFTGift
    public let pointsSpent: Int
    public let newLevel: Int
}

/// Deterministic local upgrade progression for the NexusNFT showcase.
public enum NexusNFTUpgradeEngine {
    public static let maximumLevel = 10

    public static func cost(toUpgrade gift: NexusNFTGift) -> Int {
        let level = max(1, gift.level)
        return 100 + (level - 1) * 75 + ((level - 1) * (level - 2) / 2) * 25
    }

    public static func upgrade(gift: NexusNFTGift, wallet: inout NexusNFTWallet) throws -> NexusNFTUpgradeResult {
        guard gift.level < maximumLevel else { throw NexusNFTUpgradeError.maximumLevel }
        let price = cost(toUpgrade: gift)
        guard wallet.upgradePoints >= price else {
            throw NexusNFTUpgradeError.insufficientPoints(required: price, available: wallet.upgradePoints)
        }
        wallet.upgradePoints -= price
        var upgraded = gift
        upgraded.level += 1
        upgraded.experience = 0
        upgraded.attributes = upgraded.attributes.map { attribute in
            var value = attribute
            if value.name.localizedCaseInsensitiveContains("level") {
                value.value = "Level \(upgraded.level)"
            }
            return value
        }
        return NexusNFTUpgradeResult(gift: upgraded, pointsSpent: price, newLevel: upgraded.level)
    }
}
