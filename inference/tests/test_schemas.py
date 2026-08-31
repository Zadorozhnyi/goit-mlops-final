"""Unit tests for the Pydantic input schema - this is what actually enforces
Block C1 (input validation), so it's worth testing directly rather than only
through a live HTTP call.
"""

import os
import sys

import pytest
from pydantic import ValidationError

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))

from schemas import IrisInput  # noqa: E402


def test_valid_input_is_accepted():
    payload = IrisInput(sepal_length=5.1, sepal_width=3.5, petal_length=1.4, petal_width=0.2)
    assert payload.sepal_length == 5.1


def test_out_of_range_value_is_rejected():
    with pytest.raises(ValidationError):
        IrisInput(sepal_length=999, sepal_width=3.5, petal_length=1.4, petal_width=0.2)


def test_negative_value_is_rejected():
    with pytest.raises(ValidationError):
        IrisInput(sepal_length=-1, sepal_width=3.5, petal_length=1.4, petal_width=0.2)


def test_wrong_type_is_rejected():
    with pytest.raises(ValidationError):
        IrisInput(sepal_length="not a number", sepal_width=3.5, petal_length=1.4, petal_width=0.2)


def test_missing_field_is_rejected():
    with pytest.raises(ValidationError):
        IrisInput(sepal_length=5.1, sepal_width=3.5, petal_length=1.4)
