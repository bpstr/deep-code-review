from dataclasses import dataclass
from enum import Enum
from typing import Protocol


class PaymentStatus(Enum):
    SUCCEEDED = "succeeded"
    DECLINED = "declined"


@dataclass(frozen=True)
class PaymentResult:
    status: PaymentStatus


class Gateway(Protocol):
    def charge(self, amount: int) -> PaymentResult: ...


class Checkout:
    def __init__(self, gateway: Gateway):
        self.gateway = gateway

    def submit(self, amount: int) -> str:
        result = self.gateway.charge(amount)
        return "paid" if result.status == PaymentStatus.SUCCEEDED else "declined"
