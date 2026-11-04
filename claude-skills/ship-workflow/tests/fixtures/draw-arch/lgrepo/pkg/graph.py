raise SystemExit(9)
from pkg.state import S
from pkg.nodes import n1, make_n2, n3, n4, n5, n6, n7, looped, n9, n10, n11, route_one

graph = StateGraph(S)
graph.add_node("one", n1)
graph.add_node("two", make_n2())
graph.add_node("three", n3)
graph.add_node("four", n4)
graph.add_node("ghost", missing_fn)
graph.add_node("five", n5)
graph.add_node("six", n6)
graph.add_node("seven", n7)
graph.add_node("eight", looped)
graph.add_node("nine", n9)
graph.add_node("ten", n10)
graph.add_node("eleven", n11)
graph.add_conditional_edges("one", route_one, {"x": "two"})
graph.add_conditional_edges("two", route_one, {"x": "three"})
