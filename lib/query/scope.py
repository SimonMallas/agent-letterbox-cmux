"""Explicit-root binding and participant discovery for the read-only v2 CLI.

All path components are pinned with no-follow directory opens and retained until
scan completion. Root authorization is the operator's responsibility; symlinked
root paths must be supplied by their actual directory path, not auto-resolved.
This is mutation detection, not an atomic snapshot or an archive move barrier.
"""
from dataclasses import replace
import os
import stat

from scanner import DIR_FLAGS, PARTICIPANT, Scan, ScopeIssue, _Scanner, _identity, _signature, scan


def collect(root, participants=None, *, max_names=100000):
    if (not isinstance(root, str) or not os.path.isabs(root) or "\0" in root
            or any(p in (".", "..") for p in root.split("/"))):
        raise ValueError("invalid_root")
    if (not isinstance(max_names, int) or isinstance(max_names, bool)
            or not 1 <= max_names <= 100000):
        raise ValueError("invalid_enumeration_limit")
    if participants is not None:
        if isinstance(participants, str):
            raise ValueError("invalid_participants")
        participants = tuple(participants)
        if not participants or any(not isinstance(p, str) or not PARTICIPANT.fullmatch(p) or p == "locks" for p in participants):
            raise ValueError("invalid_participants")
    declared = tuple(sorted(set(participants or ())))
    result = Scan(declared, (), ())
    observer = _Scanner(max_names)
    descriptors, bindings = [], []
    refusal_code = "root_unavailable_or_changed"
    try:
        descriptors.append(os.open("/", DIR_FLAGS))
        for component in filter(None, root.split("/")):
            parent = descriptors[-1]
            binding = os.stat(component, dir_fd=parent, follow_symlinks=False)
            if stat.S_ISLNK(binding.st_mode):
                refusal_code = "root_component_symlink"
                raise OSError("symlink root component")
            if not stat.S_ISDIR(binding.st_mode):
                refusal_code = "root_component_not_directory"
                raise OSError("unsafe root component")
            child = os.open(component, DIR_FLAGS, dir_fd=parent)
            descriptors.append(child)
            if _identity(binding) != _identity(os.fstat(child)):
                refusal_code = "root_binding_changed"
                raise OSError("root component changed")
            bindings.append((parent, component, child))
        root_fd = descriptors[-1]
        initial = os.fstat(root_fd)
        if participants is None:
            before_names = observer.names(root_fd, ".")
            # Every matching name is a candidate, even a symlink/non-directory:
            # scan must refuse those rather than silently hiding a possible seat.
            declared = tuple(n for n in before_names if PARTICIPANT.fullmatch(n) and n != "locks")
        result = scan(root_fd, declared, max_names=max_names)
        if participants is None and before_names != observer.names(root_fd, "."):
            observer.issue(".", "participant_discovery_changed")
        if _signature(initial) != _signature(os.fstat(root_fd)):
            observer.issue(".", "root_changed")
        for parent, component, child in bindings:
            binding = os.stat(component, dir_fd=parent, follow_symlinks=False)
            if not stat.S_ISDIR(binding.st_mode) or _identity(binding) != _identity(os.fstat(child)):
                observer.issue(".", "root_binding_changed")
    except OSError:
        observer.issue(".", refusal_code)
    finally:
        for fd in reversed(descriptors):
            os.close(fd)
    return replace(result, scope_issues=tuple(dict.fromkeys(result.scope_issues + tuple(observer.issues))))
