from value_store import ValueStore


def test_put_stores_value():
    store = ValueStore()
    store.put(1, 0)
    assert store.get(1) == 0
