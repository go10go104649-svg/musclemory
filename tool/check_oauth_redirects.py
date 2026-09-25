#!/usr/bin/env python3
"""Read-only preflight for app callbacks and the linked Supabase allow list.

Run before distributing either app. --local-only skips the hosted configuration.
Requires a Supabase CLI with `config diff` schema_version 1 for the remote check.
Does not print credentials or change any hosted configuration.
"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
ANDROID = '{http://schemas.android.com/apk/res/android}'


def require(ok, message):
    if not ok:
        raise ValueError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local-only', action='store_true')
    args = parser.parse_args()
    source = (ROOT / 'lib/config/auth_redirects.dart').read_text()
    callbacks = dict(re.findall(r"static const (setkeep|trainer|legacy) = '([^']+)';", source))
    require(set(callbacks) == {'setkeep', 'trainer', 'legacy'}, 'Callback constants are missing')
    require(len({urlparse(uri).scheme for uri in callbacks.values()}) == 3, 'App URL schemes overlap')
    require('redirectUrl: AuthRedirects.trainer' in (ROOT / 'apps/setkeep_trainer/lib/main.dart').read_text(), 'TRAINER is not using its callback constant')
    require('authRedirectUrl = AuthRedirects.setkeep' in (ROOT / 'lib/config/supabase_config.dart').read_text(), 'SETKEEP default callback changed')
    for app, directory, expected_id in [('setkeep', ROOT, 'com.setkeep.app'), ('trainer', ROOT / 'apps/setkeep_trainer', 'com.setkeep.trainer')]:
        uri = urlparse(callbacks[app])
        require(uri.hostname == 'login-callback' and uri.path == '/', f'{app}: noncanonical callback')
        manifest = ET.parse(directory / 'android/app/src/main/AndroidManifest.xml').getroot()
        matching = []
        accepted_schemes = set()
        for intent in manifest.findall('.//intent-filter'):
            for data in intent.findall('data'):
                scheme, host = data.get(ANDROID + 'scheme'), data.get(ANDROID + 'host')
                accepted_schemes.add(scheme)
                if scheme == uri.scheme and host == uri.hostname:
                    matching.append(intent)
        require(len(matching) == 1, f'{app}: callback intent-filter is missing or duplicated')
        require(any(e.get(ANDROID + 'name') == 'android.intent.category.BROWSABLE' for e in matching[0].findall('category')), f'{app}: callback is not browsable')
        other = 'setkeep' if app == 'trainer' else 'trainer'
        require(urlparse(callbacks[other]).scheme not in accepted_schemes, f'{app}: claims another app scheme')
        if app == 'trainer':
            require(urlparse(callbacks['legacy']).scheme not in accepted_schemes, 'trainer: claims legacy SETKEEP scheme')
        require(any(e.get(ANDROID+'name') == 'flutter_deeplinking_enabled' and e.get(ANDROID+'value') == 'false' for e in manifest.findall('.//meta-data')), f'{app}: Flutter competes with app_links')
        gradle = (directory / 'android/app/build.gradle.kts').read_text()
        require(re.search(r'applicationId\s*=\s*"' + re.escape(expected_id) + '"', gradle), f'{app}: incorrect Android identity')
        with (directory / 'ios/Runner/Info.plist').open('rb') as handle:
            info = plistlib.load(handle)
        schemes = {scheme for entry in info.get('CFBundleURLTypes', []) for scheme in entry.get('CFBundleURLSchemes', [])}
        require(uri.scheme in schemes and urlparse(callbacks[other]).scheme not in schemes, f'{app}: iOS callback scheme mismatch')
        if app == 'trainer':
            require(urlparse(callbacks['legacy']).scheme not in schemes, 'trainer: claims legacy iOS scheme')
        require(info.get('FlutterDeepLinkingEnabled') is False, f'{app}: iOS Flutter competes with app_links')
        xcode = (directory / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        require(f'PRODUCT_BUNDLE_IDENTIFIER = {expected_id};' in xcode, f'{app}: incorrect iOS identity')
        print(f'PASS {app}: Android/iOS {expected_id} -> {callbacks[app]}')
    config = (ROOT / 'supabase/config.toml').read_text()
    line = re.search(r'^additional_redirect_urls\s*=\s*(\[[^\n]*\])', config, re.M)
    require(line is not None, 'Local allow list missing')
    local_urls = json.loads(line.group(1))
    require(set(callbacks.values()).issubset(local_urls), 'Local allow list misses an app callback')
    if not args.local_only:
        result = subprocess.run(['supabase', 'config', 'diff'], cwd=ROOT, capture_output=True, text=True)
        require(result.returncode == 0, 'Unable to inspect linked Supabase configuration; check CLI authentication')
        data = json.loads(result.stdout)
        require(data.get('schema_version') == 1, 'Unsupported CLI diff format')
        require('auth' in data.get('scope', {}).get('present', []), 'Hosted Auth configuration was not returned')
        change = next((c for c in data['changes'] if c['path'] == ['auth', 'additional_redirect_urls']), None)
        remote_urls = local_urls if change is None else (change['remote'] or [])
        missing = set(callbacks.values()) - set(remote_urls)
        require(not missing, 'Hosted allow list missing: ' + ', '.join(sorted(missing)))
        print('PASS linked Supabase: all app callbacks explicitly allowed')
    print('OAuth callback preflight passed')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, ET.ParseError, KeyError, TypeError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
