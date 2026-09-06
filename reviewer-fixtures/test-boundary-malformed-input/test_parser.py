import pytest

from parser import InvalidRequest, parse_request


def test_rejects_malformed_public_request_body():
    # First-party clients never send this, but the public HTTP boundary can receive it.
    with pytest.raises(InvalidRequest, match="invalid request body"):
        parse_request(b"{not-json")
