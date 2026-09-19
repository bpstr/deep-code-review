def http_eligible(order):
    if not order.paid:
        return False
    if order.cancelled:
        return False
    if order.address is None:
        return False
    return order.weight <= 30


def batch_eligible(order):
    if not order.paid:
        return False
    if order.cancelled:
        return False
    if order.address is None:
        return False
    return order.weight <= 30
