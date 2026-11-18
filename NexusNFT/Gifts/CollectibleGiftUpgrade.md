# NexusNFT — collectible gift upgrade

This feature upgrades an actual Telegram regular Star Gift into a Telegram collectible gift. It is not an app-local level/XP system.

## Required flow

1. Read the owned gift from Telegram's saved-gifts/message data.
2. Enable Upgrade only when Telegram marks the gift eligible (can_upgrade) or reports a prepaid upgrade.
3. Request Telegram's upgrade preview using payments.getStarGiftUpgradePreview. Show the official upgrade price and possible model, pattern and backdrop attributes returned by Telegram.
4. If the sender prepaid the upgrade, invoke payments.upgradeStarGift directly with the saved-gift reference and appropriate flags.
5. Otherwise, request a payment form using inputInvoiceStarGiftUpgrade, present Telegram's normal Stars payment confirmation, and complete the official payment flow.
6. Refresh the saved-gift collection from Telegram updates. The server returns the upgraded collectible and its real attributes/unique identity.
7. Offer the normal profile display controls for the resulting collectible.

## Important rules

- Never fabricate a collectible, unique number, rarity, ownership or blockchain state locally.
- Never treat a locally drawn NFT skin as an actual Telegram collectible.
- Respect Telegram's can_upgrade, upgrade_stars, prepaid-upgrade and already-upgraded states.
- Preserve original sender/message details only when the user selects Telegram's keep_original_details option.
- The operation is server-authoritative and may require Telegram Stars. NexusNFT must not bypass payment or eligibility checks.

## Telegram API references

- payments.getStarGiftUpgradePreview: official price/attribute preview.
- inputInvoiceStarGiftUpgrade: payment invoice for a paid upgrade.
- payments.upgradeStarGift: completes an already-prepaid upgrade.
- Telegram emits the upgraded collectible gift in its updates.

Official documentation: https://core.telegram.org/api/gifts
