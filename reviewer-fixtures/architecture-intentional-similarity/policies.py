def billing_rebate(invoice):
    return invoice.paid and invoice.total >= 100


def shipping_credit(shipment):
    return shipment.delivered and shipment.total >= 100
