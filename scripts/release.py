#!/usr/bin/env python3
"""Version, notes and checksum tooling; no third-party dependencies."""
import argparse
import hashlib
import json
import platform
import plistlib
import re
import sys
from pathlib import Path

VERSION = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)')

def version(value):
    if not VERSION.fullmatch(value):
        raise ValueError('Use a stable version such as 1.1.0; prerelease suffixes are not supported')
    return tuple(map(int, value.split('.')))

def metadata(root, tag=None):
    info = plistlib.loads((root / 'Info.plist').read_bytes())
    current = info['CFBundleShortVersionString']
    version(current)
    build = str(info['CFBundleVersion'])
    if not build.isdecimal() or int(build) < 1:
        raise ValueError('CFBundleVersion must be a positive integer')
    if info['CFBundleIdentifier'] != 'local.macostoolset.app':
        raise ValueError('Unexpected application identifier')
    if tag is not None and tag != 'v' + current:
        raise ValueError('Release tag must exactly match Info.plist: v' + current)
    return {'version': current, 'build': build, 'minimum_macos': info['LSMinimumSystemVersion'], 'architecture': platform.machine()}

def notes(root, release_version):
    version(release_version)
    text = (root / 'CHANGELOG.md').read_text()
    sections = list(re.finditer(r'^## \[([^\]]+)\].*$', text, re.MULTILINE))
    matches = [i for i, heading in enumerate(sections) if heading.group(1) == release_version]
    if len(matches) != 1:
        raise ValueError('CHANGELOG.md must contain exactly one section for ' + release_version)
    i = matches[0]
    body = text[sections[i].end():sections[i + 1].start() if i + 1 < len(sections) else len(text)].strip()
    if not body:
        raise ValueError('Release notes are empty')
    return body + '\n'

def checksums(paths):
    names = [p.name for p in paths]
    if len(names) != len(set(names)) or not paths:
        raise ValueError('Artifact names must be unique and nonempty')
    lines = []
    for path in sorted(paths, key=lambda p: p.name):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+', path.name) or not path.is_file() or path.is_symlink():
            raise ValueError('Invalid artifact: ' + str(path))
        digest = hashlib.sha256()
        with path.open('rb') as file:
            for block in iter(lambda: file.read(1024 * 1024), b''):
                digest.update(block)
        lines.append(digest.hexdigest() + '  ' + path.name)
    return '\n'.join(lines) + '\n'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    commands = parser.add_subparsers(dest='command', required=True)
    meta = commands.add_parser('metadata'); meta.add_argument('--tag'); meta.add_argument('--field', choices=['version', 'build', 'minimum_macos', 'architecture'])
    note = commands.add_parser('notes'); note.add_argument('version')
    bump = commands.add_parser('bump'); bump.add_argument('version')
    checksum = commands.add_parser('checksums'); checksum.add_argument('paths', type=Path, nargs='+')
    args = parser.parse_args()
    try:
        if args.command == 'metadata':
            data = metadata(args.root, args.tag)
            print(data[args.field] if args.field else json.dumps(data, sort_keys=True))
        elif args.command == 'notes':
            print(notes(args.root, args.version), end='')
        elif args.command == 'bump':
            old = metadata(args.root)
            if version(args.version) <= version(old['version']):
                raise ValueError('New version must be greater than the current version')
            path = args.root / 'Info.plist'
            info = plistlib.loads(path.read_bytes())
            info['CFBundleShortVersionString'] = args.version
            info['CFBundleVersion'] = str(int(old['build']) + 1)
            temporary = path.with_suffix('.plist.tmp')
            temporary.write_bytes(plistlib.dumps(info, sort_keys=False))
            temporary.replace(path)
            print(args.version)
        else:
            print(checksums(args.paths), end='')
    except (ValueError, KeyError, OSError, plistlib.InvalidFileException) as error:
        parser.exit(1, 'Release error: ' + str(error) + '\n')

if __name__ == '__main__':
    main()
