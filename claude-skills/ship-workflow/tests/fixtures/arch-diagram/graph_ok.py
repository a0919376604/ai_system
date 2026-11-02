raise SystemExit(9)
from langgraph.graph import StateGraph, START, END

g = StateGraph(dict)
g.add_node("a", f)
g.add_node("b", f)
g.add_edge(START, "a")
g.add_conditional_edges("a", route, {"go": "b", "stop": END})
g.add_edge("b", END)
