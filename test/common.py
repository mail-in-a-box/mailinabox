import uuid


def random_id():
    return uuid.uuid4().hex[:8]
