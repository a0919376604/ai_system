raise SystemExit(9)
import functools


def n1(state):
    state["a"]
    state.get("b")
    return {"c": 1}


def make_n2():
    def n2(st):
        st["c"]
        out = {}
        out["d"] = 1
        return out
    return n2


def n3(state):
    state["a"]
    return helper(state)


def n4(state):
    state["a"]
    state["b"] = 2


n5 = functools.partial(n1)


async def n6(state):
    state["a"]
    return {**state, "c": 1}


def n7(**kw):
    return {}


from pkg.nodes import helpers


def log(x):
    x["a"]


def rec(s):
    return rec(s)


def n9(state):
    return helpers.fill(state)


def n10(state):
    log(state)
    helpers.deep(state)
    return {}


def n11(state):
    return rec(state)


def route_one(state):
    return state["b"]
