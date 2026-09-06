import json


class InvalidRequest(ValueError):
    pass


def parse_request(raw: bytes) -> dict:
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InvalidRequest("invalid request body") from exc

    if not isinstance(payload, dict):
        raise InvalidRequest("request body must be an object")

    return payload
