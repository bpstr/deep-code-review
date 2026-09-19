from typing import Protocol

class Sender(Protocol):
    def send(self, message: str) -> None: ...

def notify(sender: Sender, message: str) -> None:
    sender.send(message)
