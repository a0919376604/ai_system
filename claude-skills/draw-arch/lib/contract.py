"""Scan LangGraph node state contracts through AST, without running source."""
import argparse
import ast
import json
import sys
from pathlib import Path

from render import SpecError, load_spec
from seams import git_output


FUNCTIONS = (ast.FunctionDef, ast.AsyncFunctionDef)


def body_nodes(function):
    """Walk one function's body, excluding other lexical scopes."""
    def walk(node):
        if isinstance(node, FUNCTIONS + (ast.ClassDef, ast.Lambda)):
            return
        yield node
        for child in ast.iter_child_nodes(node):
            yield from walk(child)
    for statement in function.body:
        yield from walk(statement)


def callee(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = callee(node.value)
        return prefix + "." + node.attr if prefix != "call" else "call"
    return "call"


def short(node) -> str:
    """A readable, bounded rendering of an expression for a partial reason."""
    if isinstance(node, ast.Call):
        return callee(node.func) + "(...)"
    text = ast.unparse(node) if hasattr(ast, "unparse") else type(node).__name__
    return text if len(text) <= 40 else text[:37] + "..."


def analyze(function, follow=None, state=None, depth=0, seen=frozenset()):
    """Reads, returned writes, mutated writes and partial reasons of one function.

    `follow(func_expr)` resolves a call target to (path, def, follow) inside the repo;
    a resolved helper that receives the state is analysed in turn, up to 3 levels deep.
    """
    if state is None:
        positional = function.args.posonlyargs + function.args.args
        if not positional:
            return set(), set(), set(), {"no state parameter"}, set()
        state = positional[0].arg
    nodes = list(body_nodes(function))
    reads, returned_writes, mutated, partial, return_partial = set(), set(), set(), set(), set()
    if any(isinstance(node, ast.Name) and node.id == state and isinstance(node.ctx, ast.Store) for node in nodes):
        # A rebound or shadowed state name makes every read and write through it unreliable.
        return set(), set(), set(), {"state rebound"}, set()
    for nested in ast.walk(function):
        if nested is not function and isinstance(nested, FUNCTIONS + (ast.Lambda,)):
            if any(isinstance(n, ast.Name) and n.id == state and isinstance(n.ctx, ast.Load) for n in ast.walk(nested)):
                partial.add("state used in nested function " + getattr(nested, "name", "lambda"))

    def named(node, name):
        return isinstance(node, ast.Name) and node.id == name

    def key(node):
        return node.value if isinstance(node, ast.Constant) and isinstance(node.value, str) else None

    def dict_keys(node):
        return {key(k) for k in node.keys if key(k) is not None} if isinstance(node, ast.Dict) else set()

    def helper(call):
        """Analyse a resolved helper the state is passed to; None when it cannot be followed."""
        if follow is None or depth >= 3:
            return None
        found = follow(call.func)
        if found is None:
            return None
        path, target, target_follow = found
        if (str(path), target.name, target.lineno) in seen:
            return set(), set(), set(), set(), set()
        params = [a.arg for a in target.args.posonlyargs + target.args.args]
        param = None
        for index, arg in enumerate(call.args):
            if named(arg, state) and index < len(params):
                param = params[index]
        for kw in call.keywords:
            if named(kw.value, state) and kw.arg in params + [a.arg for a in target.args.kwonlyargs]:
                param = kw.arg
        if param is None:
            return None
        return analyze(target, target_follow, param, depth + 1, seen | {(str(path), target.name, target.lineno)})

    returned = {node.value.id for node in nodes if isinstance(node, ast.Return) and isinstance(node.value, ast.Name)}
    dictionaries = set()
    for node in nodes:
        if isinstance(node, (ast.Assign, ast.AnnAssign)) and isinstance(node.value, ast.Dict):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            dictionaries.update(t.id for t in targets if isinstance(t, ast.Name) and t.id in returned)
    def unwrap(value):
        return value.value if isinstance(value, ast.Await) else value

    returned_calls = {id(unwrap(node.value)) for node in nodes
                      if isinstance(node, ast.Return) and isinstance(unwrap(node.value), ast.Call)}
    for node in nodes:
        if isinstance(node, ast.Subscript) and key(node.slice) is not None:
            if named(node.value, state) and isinstance(node.ctx, ast.Load):
                reads.add(key(node.slice))
            if isinstance(node.ctx, ast.Store):
                if named(node.value, state):
                    mutated.add(key(node.slice))
                elif isinstance(node.value, ast.Name) and node.value.id in dictionaries:
                    returned_writes.add(key(node.slice))
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if any(isinstance(t, ast.Name) and t.id in dictionaries for t in targets):
                returned_writes.update(dict_keys(node.value))
        if isinstance(node, ast.Return) and node.value is not None:
            value = unwrap(node.value)
            if isinstance(value, ast.Dict):
                returned_writes.update(dict_keys(value))
                for k, v in zip(value.keys, value.values):
                    if k is None and not named(v, state):
                        return_partial.add("return {**" + short(v) + "}")
            elif isinstance(value, ast.Name) and (value.id in dictionaries or value.id == state):
                pass
            elif isinstance(value, ast.Call):
                pass  # handled with the call below
            else:
                return_partial.add("return " + short(value))
        if isinstance(node, ast.Call):
            func = node.func
            state_method = isinstance(func, ast.Attribute) and named(func.value, state)
            if state_method and func.attr == "get" and node.args and key(node.args[0]) is not None:
                reads.add(key(node.args[0]))
            if (isinstance(func, ast.Attribute) and func.attr == "update" and
                    isinstance(func.value, ast.Name) and func.value.id in dictionaries):
                for arg in node.args:
                    returned_writes.update(dict_keys(arg))
                    if not isinstance(arg, ast.Dict):
                        partial.add(func.value.id + ".update(" + short(arg) + ")")
                returned_writes.update(kw.arg for kw in node.keywords if kw.arg is not None)
            passes_state = not state_method and any(
                named(arg, state) for arg in node.args + [kw.value for kw in node.keywords])
            result = helper(node) if passes_state else None
            if result is not None:
                h_reads, h_returned, h_mutated, h_partial, h_return_partial = result
                reads |= h_reads
                mutated |= h_mutated
                partial |= h_partial
                if id(node) in returned_calls:
                    returned_writes |= h_returned
                    return_partial |= h_return_partial
            else:
                if passes_state:
                    partial.add("state passed to " + callee(func))
                if id(node) in returned_calls:
                    return_partial.add("return " + callee(func) + "(...)")
    return reads, returned_writes, mutated, partial, return_partial


def scan(repo: str, graph: dict) -> dict:
    base = Path(repo).resolve()
    if not base.is_dir():
        raise ValueError("not a repository: " + repo)

    def within(path):
        path = path.resolve()
        path.relative_to(base)
        return path

    roots = [within(base / root) for root in graph["roots"]]
    graph_file = within(base / graph["file"])
    trees = {}

    def tree(path):
        if path not in trees:
            trees[path] = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        return trees[path]

    def module_file(module, parents):
        for parent in parents:
            path = parent.joinpath(*module.split(".")) if module else parent
            for candidate in (path.with_suffix(".py"), path / "__init__.py"):
                try:
                    candidate = within(candidate)
                except ValueError:
                    continue  # resolves outside the repo: leave the name unresolved
                if candidate.is_file():
                    return candidate
        return None

    def resolve(path, name, hops=0, kinds=FUNCTIONS):
        if path is None or hops > 5:
            return None
        try:
            statements = tree(path).body
        except (OSError, UnicodeError, SyntaxError, ValueError):
            return None
        for node in statements:
            if isinstance(node, (ast.Assign, ast.AnnAssign)):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                if any(isinstance(t, ast.Name) and t.id == name for t in targets):
                    return None
        for node in statements:
            if isinstance(node, kinds) and node.name == name:
                return path, node
            if isinstance(node, ast.ImportFrom):
                for alias in node.names:
                    if (alias.asname or alias.name) != name:
                        continue
                    parents = roots
                    if node.level:
                        parent = path.parent
                        for _ in range(node.level - 1):
                            parent = parent.parent
                        parents = [parent]
                    target = module_file(node.module, parents)
                    return resolve(target, alias.name, hops + 1, kinds)
        return None

    def module_alias(path, name):
        """The module file a bare name refers to in `path` (`import a.b as m`, `from a import b`)."""
        try:
            statements = tree(path).body
        except (OSError, UnicodeError, SyntaxError, ValueError):
            return None
        for node in statements:
            if isinstance(node, ast.Import):
                for alias in node.names:
                    if (alias.asname or alias.name) == name:
                        return module_file(alias.name, roots)
            if isinstance(node, ast.ImportFrom):
                for alias in node.names:
                    if (alias.asname or alias.name) != name:
                        continue
                    parents = roots
                    if node.level:
                        parent = path.parent
                        for _ in range(node.level - 1):
                            parent = parent.parent
                        parents = [parent]
                    dotted = ".".join(filter(None, [node.module, alias.name]))
                    return module_file(dotted, parents)
        return None

    def follower(path):
        def follow(func):
            found = None
            if isinstance(func, ast.Name):
                found = resolve(path, func.id)
            elif isinstance(func, ast.Attribute) and isinstance(func.value, ast.Name):
                target = module_alias(path, func.value.id)
                found = resolve(target, func.attr) if target else None
            return (found[0], found[1], follower(found[0])) if found else None
        return follow

    def facts(path, function, router=False):
        reads, returned, mutated, partial, return_partial = analyze(function, follower(path))
        # A router returns the next node's name, never a state update.
        return sorted(reads), sorted(returned | mutated), sorted(partial if router else partial | return_partial)

    graph_tree = tree(graph_file)
    state = resolve(graph_file, graph["state"], kinds=(ast.ClassDef,))
    if state is None:
        raise ValueError("state class not found: " + graph["state"])
    declared = sorted({n.target.id for n in state[1].body
                       if isinstance(n, ast.AnnAssign) and isinstance(n.target, ast.Name)})
    def keyword(call, name):
        return next((kw.value for kw in call.keywords if kw.arg == name), None)

    calls = sorted((n for n in ast.walk(graph_tree) if isinstance(n, ast.Call) and
                    isinstance(n.func, ast.Attribute) and n.func.attr == "add_node"),
                   key=lambda n: (n.lineno, n.col_offset))
    nodes = []
    for call in calls:
        first = call.args[0] if call.args else None
        if isinstance(first, ast.Constant) and isinstance(first.value, str):
            node_id, expression = first.value, call.args[1] if len(call.args) >= 2 else keyword(call, "action")
        elif isinstance(first, ast.Name) and len(call.args) == 1:
            node_id, expression = first.id, first  # LangGraph names the node after the function
        else:
            node_id, expression = "line-{}".format(call.lineno), None  # a name the scanner cannot read
        found = None
        if isinstance(expression, ast.Name):
            found = resolve(graph_file, expression.id)
        elif isinstance(expression, ast.Call) and isinstance(expression.func, ast.Name):
            factory = resolve(graph_file, expression.func.id)
            if factory:
                returned = {n.value.id for n in body_nodes(factory[1])
                            if isinstance(n, ast.Return) and isinstance(n.value, ast.Name)}
                inner = next((n for n in factory[1].body if isinstance(n, FUNCTIONS) and n.name in returned), None)
                if inner is not None:
                    found = factory[0], inner
        node = {"id": node_id, "kind": "node", "file": "", "line": 0,
                "reads": [], "writes": [], "partial": [], "resolved": found is not None}
        if found:
            path, function = found
            node.update(file=path.relative_to(base).as_posix(), line=function.lineno)
            node["reads"], node["writes"], node["partial"] = facts(path, function)
        nodes.append(node)
    routers = {}
    for call in sorted((n for n in ast.walk(graph_tree) if isinstance(n, ast.Call) and
                        isinstance(n.func, ast.Attribute) and n.func.attr == "add_conditional_edges"),
                       key=lambda n: (n.lineno, n.col_offset)):
        path_fn = call.args[1] if len(call.args) >= 2 else keyword(call, "path")
        if not isinstance(path_fn, ast.Name):
            continue
        name = path_fn.id
        if name in routers:
            continue
        found = resolve(graph_file, name)
        router = {"id": name, "kind": "router", "file": "", "line": 0,
                  "reads": [], "writes": [], "partial": [], "resolved": found is not None}
        if found:
            router.update(file=found[0].relative_to(base).as_posix(), line=found[1].lineno)
            router["reads"], router["writes"], router["partial"] = facts(*found, router=True)
        routers[name] = router
    return {"nodes": nodes + list(routers.values()), "declared": declared}


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo")
    parser.add_argument("spec")
    args = parser.parse_args(argv)
    try:
        spec = load_spec(args.spec)
        from check import check_spec
        findings = check_spec(spec)
        if findings:
            raise ValueError("\n".join(findings))
        if spec.get("page") != "contract":
            raise ValueError("spec.page must be contract")
        actual = scan(args.repo, spec["graph"])
        commit = git_output(args.repo, "rev-parse", "HEAD").strip()
        previous = {node["id"]: node for node in spec["nodes"]}
        for node in actual["nodes"]:
            for field in ("verdict", "note"):
                if field in previous.get(node["id"], {}):
                    node[field] = previous[node["id"]][field]
        spec.update(actual)
        spec["repo"]["commit"] = commit
        Path(args.spec).write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except (SpecError, OSError, UnicodeError, SyntaxError, ValueError) as exc:
        print("contract: " + str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
