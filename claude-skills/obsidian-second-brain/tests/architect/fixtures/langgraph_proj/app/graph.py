from langgraph.graph import StateGraph
from app.core.state import CustomerState
from app.nodes.intent import classify_intent
from app.nodes.retrieve import retrieve_docs
from app.nodes.generate import generate_answer

def build_graph():
    g = StateGraph(CustomerState)
    g.add_node("intent", classify_intent)
    g.add_node("retrieve", retrieve_docs)
    g.add_node("generate", generate_answer)
    g.set_entry_point("intent")
    g.add_edge("intent", "retrieve")
    g.add_edge("retrieve", "generate")
    return g.compile()
