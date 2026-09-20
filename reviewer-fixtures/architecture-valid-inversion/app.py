from domain import notify

class ConsoleSender:
    def send(self, message: str) -> None:
        print(message)

notify(ConsoleSender(), "hello")
