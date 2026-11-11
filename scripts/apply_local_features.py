#!/usr/bin/env python3
"""Enable local Swiftgram Pro UI/features in an independent open-source fork.

Does NOT spoof receipts, replace remote subscriptions, or unlock Telegram Premium.
Uses exact anchored replacements, aborting on incompatible sources.
"""
from __future__ import annotations
import argparse
import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Rule:
    file: str
    before: str
    after: str
    reason: str


RULES = [
    Rule(
        'Swiftgram/SGStatus/Sources/SGStatus.swift',
        '    public var status: Int64\n',
        '    public var status: Int64\n\n'
        '    // Independent fork: local, on-device features are available to everyone.\n'
        '    // Keep `status` unchanged; it represents the server-issued subscription state.\n'
        '    public var localFeaturesEnabled: Bool {\n'
        '        return true\n'
        '    }\n',
        'Independent local capability flag; leave real subscription untouched',
    ),
    Rule(
        'Swiftgram/SGTelegramUIExtensions/Sources/SGTelegramUIExtensions.swift',
        'if context.sharedContext.immediateSGStatus.status > 1 {',
        'if context.sharedContext.immediateSGStatus.localFeaturesEnabled {',
        'Open local Pro settings from internal links',
    ),
    Rule(
        'Swiftgram/SGPeerInfoRows/Sources/SGPeerInfoRows.swift',
        'if paymentsEnabled || context.sharedContext.immediateSGStatus.status > 1 {',
        'if paymentsEnabled || context.sharedContext.immediateSGStatus.localFeaturesEnabled {',
        'Show feature settings in profile',
    ),
    Rule(
        'Swiftgram/SGProUI/Sources/AppBadgeSelectorController.swift',
        'if self.context.sharedContext.immediateSGStatus.status > 1 {',
        'if self.context.sharedContext.immediateSGStatus.localFeaturesEnabled {',
        'Allow choosing local notification badge',
    ),
    Rule(
        'submodules/TelegramUI/Components/MessageInputPanelComponent/Sources/MessageInputPanelComponent.swift',
        'guard context.sharedContext.immediateSGStatus.status > 1 else { return }',
        'guard context.sharedContext.immediateSGStatus.localFeaturesEnabled else { return }',
        'Enable new chat input formatting toolbar',
    ),
    Rule(
        'submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift',
        'guard context.sharedContext.immediateSGStatus.status > 1 else { return }',
        'guard context.sharedContext.immediateSGStatus.localFeaturesEnabled else { return }',
        'Enable legacy chat input formatting toolbar',
    ),
    Rule(
        'submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreenSettingsActions.swift',
        'if self.context.sharedContext.immediateSGStatus.status > 1 {',
        'if self.context.sharedContext.immediateSGStatus.localFeaturesEnabled {',
        'Open local settings instead of purchase screen',
    ),
    Rule(
        'submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift',
        'icon.isSGPro && context.sharedContext.immediateSGStatus.status < 2',
        'icon.isSGPro && !context.sharedContext.immediateSGStatus.localFeaturesEnabled',
        'Allow Swiftgram local app icon selection',
    ),
    Rule(
        'submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift',
        'let isPremium = sgStatus.status > 1',
        'let isPremium = sgStatus.localFeaturesEnabled',
        'Remove local icon lock badge (does not affect Telegram Premium)',
    ),
]


def apply(source: Path, verify_only: bool) -> dict:
    if not (source / 'versions.json').is_file():
        raise SystemExit(f'Not a Swiftgram source root: {source}')
    v = json.loads((source / 'versions.json').read_text(encoding='utf-8'))
    if v.get('app') != '13.1.3':
        raise SystemExit(f"Expected Swiftgram 13.1.3, got {v.get('app')!r}. Pick a matching source ref.")
    contents: dict[str, str] = {}
    changed = []
    for rule in RULES:
        if rule.file not in contents:
            contents[rule.file] = (source / rule.file).read_text(encoding='utf-8')
        content = contents[rule.file]
        if rule.after in content:
            state = 'already applied'
        elif content.count(rule.before) == 1:
            contents[rule.file] = content.replace(rule.before, rule.after, 1)
            state = 'valid' if verify_only else 'updated'
        else:
            raise SystemExit(f'Patch mismatch in {rule.file}: {rule.reason}. Stop; do not guess.')
        changed.append((rule.file, rule.reason, state))

    if not verify_only:
        for relative_path, content in contents.items():
            (source / relative_path).write_text(content, encoding='utf-8')

    for file, reason, state in changed:
        print(f'[{state}] {file}: {reason}')
    print(f"Verified {len(RULES)} changes to {len(contents)} Swift files (source {v['app']}).")
    print('Server status, purchases, and Telegram Premium were NOT changed.')
    return contents


def main():
    p = argparse.ArgumentParser()
    p.add_argument('source', type=Path, help='Path to upstream Swiftgram source root')
    p.add_argument('--check-only', action='store_true')
    opts = p.parse_args()
    apply(opts.source.resolve(), opts.check_only)


if __name__ == '__main__':
    main()
