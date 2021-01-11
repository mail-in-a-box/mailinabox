def safe_int(str, default_value=0):
    try:
        return int(str)
    except ValueError:
        return default_value

def safe_append(d, key, value):
    if key not in d:
        d[key] = [ value ]
    else:
        d[key].append(value)
    return d

def safe_del(d, key):
    if key in d:
        del d[key]
    return d

