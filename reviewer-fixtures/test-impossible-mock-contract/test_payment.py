from types import SimpleNamespace
from unittest.mock import Mock

from payment import Checkout


def test_unknown_gateway_status_is_declined():
    gateway = Mock()
    # The real Gateway contract returns PaymentResult with a PaymentStatus enum.
    # This mock invents a third state that the real implementation cannot return.
    gateway.charge.return_value = SimpleNamespace(status="pending")

    checkout = Checkout(gateway)

    assert checkout.submit(1000) == "declined"
