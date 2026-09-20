The immutable record is a transport DTO, not a domain aggregate. Validation of untrusted input lives in parse_payload. Pure data with external validation is intentional.
