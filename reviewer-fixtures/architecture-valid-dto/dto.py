from dataclasses import dataclass

@dataclass(frozen=True)
class PersonPayload:
    name: str

def parse_payload(raw):
    name = raw.get("name")
    if not isinstance(name, str) or not name.strip():
        raise ValueError("name required")
    return PersonPayload(name.strip())
