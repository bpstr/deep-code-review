def transfer(db, queue, source, target, amount):
    db.debit_and_commit(source, amount)
    queue.publish({"target": target, "credit": amount})
    return {"success": True}
