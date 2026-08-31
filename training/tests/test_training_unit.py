"""Unit tests for the pure helper functions in train_and_push.py - the ones
that don't need a real MLflow server. The full training+registry flow is
covered separately in test_training_integration.py.
"""

import hashlib
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from train_and_push import get_dataset_version, get_git_commit_sha, sha256_of_file  # noqa: E402
import numpy as np


def test_dataset_version_is_deterministic():
    X = np.array([[1.0, 2.0], [3.0, 4.0]])
    y = np.array([0, 1])
    assert get_dataset_version(X, y) == get_dataset_version(X.copy(), y.copy())


def test_dataset_version_changes_with_data():
    X1 = np.array([[1.0, 2.0]])
    X2 = np.array([[1.0, 2.1]])
    y = np.array([0])
    assert get_dataset_version(X1, y) != get_dataset_version(X2, y)


def test_dataset_version_is_short_hex():
    X = np.array([[1.0, 2.0]])
    y = np.array([0])
    version = get_dataset_version(X, y)
    assert len(version) == 12
    int(version, 16)  # raises ValueError if it isn't hex


def test_sha256_of_file_matches_hashlib(tmp_path):
    f = tmp_path / "model.pkl"
    f.write_bytes(b"not a real model, just some bytes")
    expected = hashlib.sha256(f.read_bytes()).hexdigest()
    assert sha256_of_file(str(f)) == expected


def test_git_commit_sha_prefers_ci_env(monkeypatch):
    monkeypatch.setenv("CI_COMMIT_SHORT_SHA", "abc1234")
    assert get_git_commit_sha() == "abc1234"


def test_git_commit_sha_falls_back_to_git(monkeypatch):
    monkeypatch.delenv("CI_COMMIT_SHORT_SHA", raising=False)
    sha = get_git_commit_sha()
    # Either a short git hash from this repo, or "unknown" if git isn't
    # available at all - both are valid outcomes, "" or an exception aren't.
    assert sha and sha != ""
