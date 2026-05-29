from pipeline.nodes.stage1 import run as stage1
from pipeline.nodes.stage2 import run as stage2
from pipeline.nodes.stage3 import run as stage3
import openai

def run_pipeline(input_data):
    x = stage1(input_data)
    y = stage2(x)
    return stage3(y)
