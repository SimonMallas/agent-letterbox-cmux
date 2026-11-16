#!/usr/bin/env python3
"""Conservative read-only accelerators; exit 3 before output to use shell fallback."""
import datetime as dt
import hashlib
import os
import re
import stat
import subprocess
import sys
import time

SAFE = re.compile(rb'^[A-Za-z0-9._:-]+$')
STAMP = re.compile(rb'^(\d{4}-\d\d-\d\dT\d{6})')
TAIL = re.compile(rb'^[0-9a-f]{8}$')


def chomp(raw):
    if raw.endswith(b'\n'):
        raw = raw[:-1]
    if raw.endswith(b'\r'):
        raw = raw[:-1]
    return raw


def fields(path):
    """Match first-field two-fence semantics, never infer values from bodies."""
    values = {}
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise OSError('not a regular file')
    with os.fdopen(fd, 'rb') as stream:
        first = stream.readline()
        if chomp(first) != b'---':
            return None
        for raw in stream:
            line = chomp(raw)
            if line == b'---':
                return values
            key, sep, value = line.partition(b':')
            if key not in values:
                values[key] = value.lstrip(b' \t\v\f\r') if sep else line
    return None


def resolve(box, ref, scope="nudge", agent="", filename_alias="false"):
    target = os.fsencode(ref)
    if not SAFE.fullmatch(target):
        return 3
    hits = []
    # Enumerate literally: the box path may itself contain glob characters.
    # Hidden seats/files remain excluded, as with the shell's ordinary glob.
    root = os.fsencode(box)
    for folder_name in ((b'inbox',) if scope in ('owned-inbox', 'own-inbox') else (b'inbox', b'processed')):
        with os.scandir(root) as seats:
            for seat in seats:
                if seat.name.startswith(b'.') or (scope != 'nudge' and seat.name != os.fsencode(agent)):
                    continue
                folder = os.path.join(root, seat.name, folder_name)
                if not os.path.isdir(folder):
                    continue
                with os.scandir(folder) as entries:
                    for entry in entries:
                        if entry.name.startswith(b'.') or not entry.name.endswith(b'.md'):
                            continue
                        if not entry.is_file(follow_symlinks=True):
                            continue
                        data = fields(entry.path)
                        if data is None:
                            continue
                        ident = data.get(b'id', b'')
                        tail = ident.rsplit(b'-', 1)[-1]
                        token = tail if TAIL.fullmatch(tail) else hashlib.sha256(ident).hexdigest()[:8].encode()
                        if ident == target or (filename_alias == 'true' and (entry.name == target or entry.name == target + b'.md')) or (TAIL.fullmatch(target) and token == target):
                            hits.append(entry.path)
                            if len(hits) > 1:
                                return 3  # Preserve legacy ambiguity formatting and ordering.
    if len(hits) != 1 or b'\n' in hits[0] or b'\r' in hits[0]:
        return 3
    sys.stdout.buffer.write(hits[0] + b'\n')
    return 0


def age(now, epoch):
    seconds = max(0, now - epoch)
    if seconds < 3600:
        return str(seconds // 60) + 'm'
    if seconds < 86400:
        return str(seconds // 3600) + 'h'
    return str(seconds // 86400) + 'd'


def sidecar(path):
    """Parse ordinary ACK/progress fields; unusual values use shell fallback."""
    found = {}
    with open(path, 'rb') as stream:
        for raw in stream:
            line = raw.rstrip(b'\n')
            for key in (b'acked_at', b'progress_at'):
                if line.startswith(key + b':') and key not in found:
                    parts = line.split(b': ')
                    found[key] = parts[1] if len(parts) > 1 else b''
            if line.startswith(b'progress:') and b'progress' not in found:
                found[b'progress'] = line[len(b'progress:'):].lstrip(b' \t\v\f\r')
    times = {}
    for key in (b'acked_at', b'progress_at'):
        raw = found.get(key, b'')
        if not raw:
            continue
        text = raw.decode('ascii')
        if re.fullmatch(r'\d{4}-\d\d-\d\dT\d{6}', text):
            fmt = '%Y-%m-%dT%H%M%S'
        elif re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', text):
            fmt = '%Y-%m-%dT%H:%M:%SZ'
        else:
            return None
        times[key] = int(dt.datetime.strptime(text, fmt).replace(tzinfo=dt.timezone.utc).timestamp())
    note = found.get(b'progress', b'').decode('ascii')
    if any(ord(c) < 32 or ord(c) > 126 for c in note):
        return None
    return times, note


def check(inbox, who, now, stale_secs, days, recent, malformed_style="path"):
    """Fast path for ordinary closed headers and simple ACK sidecars."""
    # Shell output preserves header bytes; avoid recoding under other locales.
    if any((stream.encoding or '').lower().replace('-', '') != 'utf8' for stream in (sys.stdout, sys.stderr)):
        return 3
    if any(c in inbox for c in '|\n\r'):
        return 3
    now, stale_secs = int(now), int(stale_secs)
    records = {}
    rows = []
    malformed = []
    entries = list(os.scandir(inbox))
    acknowledgements = {}
    for ent in entries:
        if ent.name.startswith('.') or not ent.name.endswith('.md.ack'):
            continue
        letter = ent.path[:-4]
        if ent.is_symlink() or not ent.is_file(follow_symlinks=False) or os.path.islink(letter) or not os.path.isfile(letter):
            return 3
        parsed = sidecar(ent.path)
        if parsed is None:
            return 3
        acknowledgements[letter] = parsed
    for ent in entries:
        name = ent.name
        if name.startswith('.'):
            continue
        if not name.endswith('.md'):
            continue
        if any(ord(c) < 32 or ord(c) > 126 or c == '|' for c in name):
            return 3
        if ent.is_symlink() or not ent.is_file(follow_symlinks=False):
            return 3
        data = fields(ent.path)
        if data is None:
            malformed.append(ent.path)
            continue
        ident = data.get(b'id', b'')
        match = STAMP.match(ident)
        if not match or not SAFE.fullmatch(ident):
            return 3
        try:
            epoch = int(dt.datetime.strptime(match.group(1).decode('ascii'), '%Y-%m-%dT%H%M%S').replace(tzinfo=dt.timezone.utc).timestamp())
            sender = data.get(b'from', b'').decode('utf-8')
            kind = data.get(b'type', b'').decode('ascii')
        except (ValueError, UnicodeError, OverflowError):
            return 3
        if any(ord(c) < 32 or 127 <= ord(c) < 160 for c in sender) or any(ord(c) < 32 or ord(c) > 126 for c in kind):
            return 3
        tail = ident.rsplit(b'-', 1)[-1]
        token = tail.decode('ascii') if TAIL.fullmatch(tail) else hashlib.sha256(ident).hexdigest()[:8]
        stamp = match.group(1).decode('ascii')
        ack = acknowledgements.get(ent.path)
        times, note = ack if ack else ({}, '')
        for value in times.values():
            epoch = max(epoch, value)
        badge = (' [ACCEPTED]' if ack else ' [UNACKED]') if data.get(b'requires_ack') == b'true' else ''
        stale = max(0, now - epoch) > stale_secs
        row = f'{epoch}|{ent.path}|{age(int(time.time()), epoch)}'
        rows.append(row)
        records[ent.path] = (stamp, token, badge, sender, kind, stale, note, times.get(b'progress_at'))
    # Delegate tie-breaking/collation to the same external sort as the shell.
    payload = ('\n'.join(rows) + ('\n' if rows else '')).encode()
    sorted_rows = subprocess.run(['sort', '-t|', '-k1,1nr'], input=payload, capture_output=True, check=True).stdout.decode('ascii').splitlines()
    live = sum(not rec[5] for rec in records.values())
    stale_count = len(records) - live
    if malformed:
        payload = ('\n'.join(malformed) + '\n').encode()
        malformed = subprocess.run(['sort'], input=payload, capture_output=True, check=True).stdout.decode('ascii').splitlines()
    def malformed_label(path):
        if malformed_style == 'path':
            return os.path.basename(path)
        stem = os.fsencode(os.path.basename(path)[:-3])
        match = STAMP.match(stem)
        stamp = match.group(1).decode('ascii') if match else 'unknown'
        tail = stem.rsplit(b'-', 1)[-1]
        token = tail.decode('ascii') if TAIL.fullmatch(tail) else hashlib.sha256(stem).hexdigest()[:8]
        return f'{stamp} · {token}'
    lines = [f'═══ MALFORMED  {malformed_label(path)}' for path in malformed]
    lines.append(f'── {who} inbox: {len(records)} message(s)  open: {live} live · {stale_count} stale (>{days}d)')
    for want_stale in (False, True):
        if want_stale and recent == 'true':
            lines.extend(['', f'{stale_count} stale items hidden; run letterbox check to see all open work'])
            break
        for row in sorted_rows:
            _, path, item_age = row.split('|')
            stamp, token, badge, sender, kind, is_stale, note, progress_epoch = records[path]
            if is_stale != want_stale:
                continue
            extra = badge + (f'  STALE {item_age}' if is_stale else '')
            lines.extend(['', f'═══ {stamp} · {token}{extra}', f'    from: {sender}  type: {kind}'])
            if note:
                suffix = f'  (age {age(int(time.time()), progress_epoch)})' if progress_epoch is not None else ''
                lines.append(f'    progress: {note}{suffix}')
    for path in malformed:
        label = path if malformed_style == 'path' else malformed_label(path)
        sys.stderr.write(f'letterbox: MALFORMED {label} (need opening and closing ---)\n')
    sys.stdout.write('\n'.join(lines) + '\n')
    return 0


def main():
    try:
        if sys.argv[1] == 'resolve':
            return resolve(*sys.argv[2:])
        if sys.argv[1] == 'check':
            return check(*sys.argv[2:])
    except (OSError, ValueError, TypeError, UnicodeError, subprocess.SubprocessError, IndexError):
        return 3
    return 3


if __name__ == '__main__':
    raise SystemExit(main())
