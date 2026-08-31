"""Request/response schemas for the inference endpoint.

Block C1 (input validation): FastAPI runs these automatically before our
code ever sees the request. A bad type or an out-of-range value never
reaches the model - `main.py`'s `validation_error_handler` turns FastAPI's
default 422 into a generic 400 with no field-level detail, so no internal
state ever leaks into an error message.

Ranges are the min/max actually seen in the Iris dataset, rounded outward a
bit. They are not a hard domain rule, just a sanity check: a request claiming
a petal length of -5 or 500 cm is a bad request, not a prediction.
"""

from pydantic import BaseModel, Field


class IrisInput(BaseModel):
    sepal_length: float = Field(ge=0, le=10, description="cm")
    sepal_width: float = Field(ge=0, le=10, description="cm")
    petal_length: float = Field(ge=0, le=10, description="cm")
    petal_width: float = Field(ge=0, le=10, description="cm")


class PredictionOutput(BaseModel):
    predicted_class: int
    class_name: str
    probabilities: list[float]
    model_name: str
    model_version: str
