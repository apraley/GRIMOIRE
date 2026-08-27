"""Generic save/load.

Objects opt in with @serializable.  The encoder walks __dict__ and emits plain
JSON; the decoder rebuilds instances without calling __init__.  Deques, sets,
tuples and the Series/Counter helpers round-trip.
"""
from __future__ import annotations

import gzip
import json
from collections import deque
from typing import Any

REGISTRY: dict[str, type] = {}

SAVE_VERSION = 3


def serializable(cls):
    REGISTRY[cls.__name__] = cls
    return cls


def _enc(o: Any) -> Any:
    if o is None or isinstance(o, (bool, int, str)):
        return o
    if isinstance(o, float):
        if o != o or o in (float("inf"), float("-inf")):
            return 0.0
        return o
    if isinstance(o, list):
        return [_enc(v) for v in o]
    if isinstance(o, tuple):
        return {"__k__": "tuple", "v": [_enc(v) for v in o]}
    if isinstance(o, set):
        return {"__k__": "set", "v": [_enc(v) for v in o]}
    if isinstance(o, frozenset):
        return {"__k__": "frozenset", "v": [_enc(v) for v in o]}
    if isinstance(o, deque):
        return {"__k__": "deque", "v": [_enc(v) for v in o], "m": o.maxlen}
    if isinstance(o, dict):
        simple = all(isinstance(k, str) for k in o)
        cname = type(o).__name__
        if simple and cname == "dict":
            return {"__d__": {k: _enc(v) for k, v in o.items()}}
        return {"__k__": "mapping", "c": cname if cname in REGISTRY else "dict",
                "v": [[_enc(k), _enc(v)] for k, v in o.items()]}
    cname = type(o).__name__
    if cname in REGISTRY:
        state = o.__getstate__() if hasattr(o, "__getstate__") else o.__dict__
        return {"__t__": cname, "f": {k: _enc(v) for k, v in state.items()}}
    raise TypeError(f"cannot serialize {cname!r} (register it with @serializable)")


def _dec(o: Any) -> Any:
    if isinstance(o, list):
        return [_dec(v) for v in o]
    if not isinstance(o, dict):
        return o
    if "__d__" in o:
        return {k: _dec(v) for k, v in o["__d__"].items()}
    kind = o.get("__k__")
    if kind == "tuple":
        return tuple(_dec(v) for v in o["v"])
    if kind == "set":
        return {_dec(v) for v in o["v"]}
    if kind == "frozenset":
        return frozenset(_dec(v) for v in o["v"])
    if kind == "deque":
        return deque((_dec(v) for v in o["v"]), maxlen=o.get("m"))
    if kind == "mapping":
        cls = REGISTRY.get(o.get("c", "dict"), dict)
        inst = cls()
        for k, v in o["v"]:
            inst[_dec(k)] = _dec(v)
        return inst
    if "__t__" in o:
        cls = REGISTRY.get(o["__t__"])
        if cls is None:
            raise TypeError(f"unknown class in save: {o['__t__']}")
        inst = cls.__new__(cls)
        state = {k: _dec(v) for k, v in o["f"].items()}
        if hasattr(cls, "__setstate__"):
            inst.__setstate__(state)
        else:
            inst.__dict__.update(state)
        return inst
    return {k: _dec(v) for k, v in o.items()}


def dumps(obj: Any) -> str:
    return json.dumps({"version": SAVE_VERSION, "root": _enc(obj)}, separators=(",", ":"))


def loads(text: str) -> Any:
    blob = json.loads(text)
    if blob.get("version") != SAVE_VERSION:
        raise ValueError(
            f"save format v{blob.get('version')} is not compatible with v{SAVE_VERSION}")
    return _dec(blob["root"])


def save_file(obj: Any, path: str) -> int:
    data = dumps(obj).encode()
    with gzip.open(path, "wb", compresslevel=6) as fh:
        fh.write(data)
    return len(data)


def load_file(path: str) -> Any:
    try:
        with gzip.open(path, "rb") as fh:
            return loads(fh.read().decode())
    except OSError:
        with open(path, "r", encoding="utf-8") as fh:
            return loads(fh.read())
