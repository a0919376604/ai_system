from typing import TypedDict, Literal

class CustomerState(TypedDict):
    user_message: str
    intent: Literal["product", "complaint", "other"]
    docs: list
    answer: str
