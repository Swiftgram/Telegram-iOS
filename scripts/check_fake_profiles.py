#!/usr/bin/env python3
"""Fail early if one of the fake provisioning profiles expires before build day."""
import datetime
import pathlib
import plistlib
import subprocess

profiles = pathlib.Path('build-system/fake-codesigning/profiles')
files = sorted(profiles.glob('*.mobileprovision'))
if len(files) != 9:
    raise SystemExit(f'Expected 9 demo profiles, found {len(files)}')
now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
for path in files:
    process = subprocess.run(['openssl', 'cms', '-verify', '-inform', 'DER',
                              '-noverify', '-in', str(path)],
                             capture_output=True, check=True)
    metadata = plistlib.loads(process.stdout)
    expiry = metadata['ExpirationDate']
    if expiry <= now:
        raise SystemExit(f'EXPIRED: {path} expired on {expiry}')
    print(f'OK: {path.name}: valid until {expiry.isoformat()}Z')
print('All fake provisioning profiles have future expiration dates.')
