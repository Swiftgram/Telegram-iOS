#!/usr/bin/env python3
"""Create an Eblogram sideload IPA config from GitHub Secrets.

Never print API hash or embed any credentials in a committed file.
"""
import json
import os
import re
from pathlib import Path

api_id = os.environ.get('TELEGRAM_API_ID', '').strip()
api_hash = os.environ.get('TELEGRAM_API_HASH', '').strip()
variant = os.environ.get('EBLOGRAM_VARIANT', 'standalone')
if variant not in {'standalone', 'full'}:
    raise SystemExit('EBLOGRAM_VARIANT must be standalone or full')
if not re.fullmatch(r'[0-9]{1,10}', api_id) or not 0 < int(api_id) <= 2_147_483_647:
    raise SystemExit('Set TELEGRAM_API_ID in GitHub Settings > Secrets and variables > Actions')
if not re.fullmatch(r'[0-9a-fA-F]{32}', api_hash):
    raise SystemExit('Set TELEGRAM_API_HASH (32 hex chars) in GitHub Actions secrets')

# Match the repository's bundled fake signing profiles for the unsigned/self-signed
# IPA. Sideloadly/AltStore must re-sign it with the user's own Apple ID and unique ID.
# This is NOT an Apple distribution certificate and is NOT suitable for TestFlight.
config = {
    'bundle_id': 'ph.telegra.Telegraph',
    'api_id': str(int(api_id)),
    'api_hash': api_hash,
    'team_id': 'C67CF9S4VU',
    'app_center_id': '0',
    'is_internal_build': 'true',
    'is_appstore_build': 'false',
    'appstore_id': '0',
    'app_specific_url_scheme': 'eblogram',
    'eblogram_standalone': variant == 'standalone',
    'premium_iap_product_id': '',
    'enable_siri': False,
    'enable_icloud': False,
    'sg_config': '',
}
out = Path('build-input/local-unsigned-configuration.json')
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'Created {out}. API credentials are intentionally not printed.')
