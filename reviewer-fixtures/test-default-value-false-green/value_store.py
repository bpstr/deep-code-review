class ValueStore:
    def __init__(self):
        self._values = {}

    def put(self, key: int, value: int) -> None:
        # BUG: value is ignored; missing keys read back as zero.
        self._values.setdefault(key, 0)

    def get(self, key: int) -> int:
        return self._values.get(key, 0)
