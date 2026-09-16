#!/usr/bin/env python3
"""Verify the App Store-signed app after export, before uploading its IPA.

Xcode may development-sign an archive and re-sign it during export. Validate
the exported .app (or .ipa), not the intermediate archive's entitlements.
"""
import argparse
from contextlib import contextmanager
import plistlib
from pathlib import Path
import subprocess
import tempfile
import zipfile

def plist(path): return plistlib.loads(path.read_bytes())
def require(value, message):
    if not value: raise SystemExit(message)

@contextmanager
def exported_app(source):
    if source.suffix == '.app':
        yield source
        return
    require(source.suffix == '.ipa', 'Provide an exported .ipa or .app; Xcode re-signs archives during export.')
    with tempfile.TemporaryDirectory(prefix='mfl-verify-export-') as directory:
        root = Path(directory)
        with zipfile.ZipFile(source) as archive:
            require(all((root / member.filename).resolve().is_relative_to(root) for member in archive.infolist()), 'Unsafe IPA paths')
        subprocess.run(['ditto', '-x', '-k', str(source), directory], check=True)
        yield root/'Payload/MFLBlitz.app'

def verify(app):
    widget = app/'PlugIns/MFLBlitzLiveActivity.appex'
    info = plist(app/'Info.plist')
    widget_info = plist(widget/'Info.plist')
    require(info['CFBundleIdentifier'] == 'com.biggsjm.MFLBlitz', 'Wrong app identity')
    require(widget_info['CFBundleIdentifier'] == 'com.biggsjm.MFLBlitz.LiveActivity', 'Wrong widget identity')
    for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
        require(info[key] == widget_info[key], f'App/widget mismatch: {key}')
    for key in ('NFLScoringURL', 'MFLBackgroundSyncURL'):
        require(info.get(key, '').startswith('https://') and '.ts.net:' in info[key], f'Missing private service URL: {key}')
    manifest = plist(app/'PrivacyInfo.xcprivacy')
    require(any(v['NSPrivacyAccessedAPIType'] == 'NSPrivacyAccessedAPICategoryUserDefaults' and 'CA92.1' in v['NSPrivacyAccessedAPITypeReasons']
                for v in manifest['NSPrivacyAccessedAPITypes']), 'Missing preference privacy reason')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    for bundle, identifier in [(app, info['CFBundleIdentifier']), (widget, widget_info['CFBundleIdentifier'])]:
        result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(bundle)], capture_output=True, check=True)
        entitlements = plistlib.loads(result.stdout)
        if bundle == app:
            require(entitlements.get('aps-environment') == 'production', 'Production push entitlement required')
        require(not entitlements.get('get-task-allow', False), 'Development debugging entitlement in distribution export')
        require(entitlements.get('application-identifier') == f'CP6ZMDE546.{identifier}', 'Wrong signing identity')
        profile = subprocess.run(['security', 'cms', '-D', '-i', str(bundle/'embedded.mobileprovision')], capture_output=True, check=True)
        provision = plistlib.loads(profile.stdout)
        require(not provision.get('ProvisionedDevices') and not provision.get('ProvisionsAllDevices', False), 'An App Store distribution profile is required')
    print(f"Validated signed {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}) export. Apple processing and push delivery still require verification.")

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('export', type=Path)
    with exported_app(parser.parse_args().export) as app:
        verify(app)
