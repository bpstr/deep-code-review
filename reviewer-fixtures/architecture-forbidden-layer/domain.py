from transport import current_request

def price():
    return 100 if current_request().headers.get("Member") else 120
