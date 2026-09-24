"""Descriptor-bound, read-only occurrence enumeration for compatibility queries.

The caller supplies an authorized open root directory and explicit participants.
No path-based reopening, body reads after the frontmatter delimiter, or mutation.
Archive layouts are unsupported and make the declared scan incomplete.
Observed stability is NOT an atomic snapshot.
"""
from __future__ import annotations

from dataclasses import dataclass
import os
import re
import stat
from types import MappingProxyType
from typing import Mapping

from envelopes import HeaderError, read_header

PARTICIPANT = re.compile(r"[a-z][a-z0-9-]*")
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
FILE_FLAGS = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK


@dataclass(frozen=True)
class Entry:
    source_ref: str
    basename: str
    location: str
    fields: Mapping[str, str] | None
    issue: str | None


@dataclass(frozen=True)
class ScopeIssue:
    source_ref: str
    code: str


@dataclass(frozen=True)
class Scan:
    participants: tuple[str, ...]
    entries: tuple[Entry, ...]
    scope_issues: tuple[ScopeIssue, ...]
    consistency: str = "non-atomic"
    folder_patterns: tuple[str, ...] = ("inbox", "processed")
    leaf_pattern: str = "*.md"
    direct_leaves_only: bool = True
    completeness_basis: str = "enumeration_and_header_syntax"

    @property
    def complete(self):
        """Scoped enumeration/header reads, NOT whole-tree absence or v1 validity."""
        return not self.scope_issues and all(e.issue is None for e in self.entries)


def _signature(info):
    # Mutation detection only: these times are NEVER publication/ordering evidence.
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns)


def _identity(info):
    return info.st_dev, info.st_ino


def _safe_name(name):
    return not any(ord(c) < 32 or ord(c) == 127 or 0xD800 <= ord(c) <= 0xDFFF
                   for c in name)


class _Scanner:
    def __init__(self, max_names):
        self.max_names = max_names
        self.entries = []
        self.issues = []
        self.issue_keys = set()

    def issue(self, ref, code):
        value = ScopeIssue(ref, code)
        if value not in self.issue_keys:
            self.issue_keys.add(value)
            self.issues.append(value)

    def names(self, fd, ref):
        # At most limit+1 names retained; the overflow name is accounted too.
        # Truncation always makes scope incomplete, never a complete absence claim.
        names = []
        try:
            with os.scandir(fd) as items:
                for item in items:
                    names.append(item.name)
                    if len(names) > self.max_names:
                        self.issue(ref, "enumeration_limit")
                        break
        except OSError:
            # Preserve every name already observed, even if iteration then fails.
            self.issue(ref, "enumeration_unreadable_or_changed")
        return sorted(names)

    def directory(self, parent, name, ref, visit, *, optional=False):
        fd = None
        try:
            try:
                binding = os.stat(name, dir_fd=parent, follow_symlinks=False)
            except FileNotFoundError:
                if not optional:
                    self.issue(ref, "missing_directory")
                return
            if not stat.S_ISDIR(binding.st_mode):
                self.issue(ref, "unsafe_directory")
                return
            fd = os.open(name, DIR_FLAGS, dir_fd=parent)
            pinned = os.fstat(fd)
            if _identity(binding) != _identity(pinned):
                self.issue(ref, "directory_changed")
                return
            names = self.names(fd, ref)
            visit(fd, ref, names)
            if names != self.names(fd, ref) or _signature(pinned) != _signature(os.fstat(fd)):
                self.issue(ref, "directory_changed")
            current = os.stat(name, dir_fd=parent, follow_symlinks=False)
            if not stat.S_ISDIR(current.st_mode) or _identity(current) != _identity(pinned):
                self.issue(ref, "directory_changed")
        except OSError:
            # Do not expose raw OS exceptions or untrusted file contents.
            self.issue(ref, "directory_unreadable_or_changed")
        finally:
            if fd is not None:
                os.close(fd)

    def leaf(self, parent, location, name):
        ref = location + "/" + name
        fd = None
        fields = None
        issue = None
        try:
            if not _safe_name(name):
                issue = "unsafe_name"
            else:
                binding = os.stat(name, dir_fd=parent, follow_symlinks=False)
                if not stat.S_ISREG(binding.st_mode):
                    issue = "unsafe_leaf"
                else:
                    fd = os.open(name, FILE_FLAGS, dir_fd=parent)
                    before = os.fstat(fd)
                    if not stat.S_ISREG(before.st_mode):
                        issue = "unsafe_leaf"
                    elif _signature(binding) != _signature(before):
                        issue = "leaf_changed"
                    else:
                        with os.fdopen(fd, "rb", buffering=0, closefd=False) as stream:
                            parsed = read_header(stream)
                        after = os.fstat(fd)
                        current = os.stat(name, dir_fd=parent, follow_symlinks=False)
                        if (_signature(before) != _signature(after)
                                or _signature(before) != _signature(current)):
                            issue = "leaf_changed"
                        else:
                            fields = MappingProxyType(parsed)
        except HeaderError as error:
            issue = str(error)  # read_header emits fixed bounded codes only.
        except OSError:
            issue = "leaf_unreadable_or_changed"
        finally:
            if fd is not None:
                os.close(fd)
        self.entries.append(Entry(ref, name, location, fields, issue))

    def leaves(self, fd, ref, names):
        for name in names:
            if name.endswith(".md"):
                self.leaf(fd, ref, name)
            else:
                # Non-letter regular sidecars are out of scope; nested trees are not.
                try:
                    mode = os.stat(name, dir_fd=fd, follow_symlinks=False).st_mode
                    if stat.S_ISDIR(mode) or stat.S_ISLNK(mode):
                        self.issue(ref + "/" + name, "unexpected_nested_entry")
                except OSError:
                    self.issue(ref + "/" + name, "entry_unreadable_or_changed")

    def participant(self, fd, ref, names):
        for name in ("inbox", "processed"):
            self.directory(fd, name, ref + "/" + name, self.leaves)
        if "archive" in names:
            self.issue(ref + "/archive", "unsupported_archive_layout")


def scan(root_fd, participants, *, max_names=100000):
    """Enumerate full declared scope, preserving occurrence and issue accounting.

    Every encountered .md name in supported leaf directories becomes one Entry,
    including unreadable/nonregular/malformed leaves. Scope issues separately
    describe unenumerable branches. Archive trees are unsupported; missing live
    folders refuse completeness, matching strict v1's required scope.

    max_names bounds each directory listing (plus one accounted overflow name).
    Results may be partial: ANY error/truncation denies complete. Callers must not
    derive answered=no/head=yes from an incomplete scan. No selection filters or
    graph verdicts are implemented here. Caller retains ownership of root_fd.
    """
    if isinstance(participants, str):
        raise ValueError("participants must be an explicit collection")
    participants = tuple(participants)
    if any(not isinstance(p, str) or not PARTICIPANT.fullmatch(p) or p == "locks"
           for p in participants):
        raise ValueError("invalid participant scope")
    names = tuple(sorted(set(participants)))
    if not isinstance(max_names, int) or isinstance(max_names, bool) or max_names < 1:
        raise ValueError("invalid enumeration limit")
    scanner = _Scanner(max_names)
    fd = os.dup(root_fd)
    try:
        initial = os.fstat(fd)
        if not stat.S_ISDIR(initial.st_mode):
            raise ValueError("root descriptor must be a directory")
        for name in names:
            scanner.directory(fd, name, name, scanner.participant)
        if _signature(initial) != _signature(os.fstat(fd)):
            scanner.issue(".", "root_changed")
    finally:
        os.close(fd)
    return Scan(names, tuple(scanner.entries), tuple(scanner.issues))
