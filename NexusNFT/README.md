# NexusNFT

A Swift module scaffold for a Swiftgram-based Telegram client customization feature.

## Included in this first implementation slice

- Local gift presentation models and attributes.
- Persistent device-local gift collection and progression wallet.
- A deterministic gift upgrade engine with levels 1–10 and escalating local point costs.
- Clear separation between local presentation/progression and Telegram server state.

## Gift upgrades

Upgrades are intentionally local-only in this scaffold. They can change the NexusNFT display level and local attributes, but they do not alter an actual Telegram collectible, its blockchain metadata, ownership, transferability, or server-side rarity. Real upgrades require an official Telegram/backend operation if Telegram exposes one.

## Integration status

This directory is a standalone module scaffold. It is not yet wired into Telegram's Bazel targets or profile/gift controllers. Integration requires inspecting the exact gift/profile APIs and adding the source files to the appropriate Swift library target(s) in Telegram/BUILD.
