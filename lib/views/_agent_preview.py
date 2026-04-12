#!/usr/bin/env python3
import sys, json, subprocess

agent_name = sys.argv[1]
data_py = sys.argv[2]

proc = subprocess.run(
    [sys.executable, data_py, "agent-detail", agent_name],
    capture_output=True,
    text=True,
)

if proc.returncode != 0:
    print("No data available")
    sys.exit(0)

try:
    d = json.loads(proc.stdout)
except json.JSONDecodeError:
    print("No data available")
    sys.exit(0)

if "error" in d:
    print(d["error"])
    sys.exit(0)

C = {
    "cyan": "\033[1m\033[38;2;136;192;208m",
    "frost": "\033[38;2;94;129;172m",
    "reset": "\033[0m",
}

print(f"{C['cyan']}{d['agent']}{C['reset']}")
print()
print(f"  Messages:  {d['messages']}")
print(f"  Sessions:  {d['sessions']}")
tok = d["tokens"]
print(f"  Input:     {tok['input']:,}")
print(f"  Output:    {tok['output']:,}")
print(f"  Reasoning: {tok['reasoning']:,}")
print(f"  Cost:      ${d['cost']:.4f}")

models = d.get("by_model", [])
if models:
    print()
    print(f"  {C['frost']}By Model:{C['reset']}")
    print(f"  {'Model':<30s} {'Msgs':>6s} {'Input':>10s} {'Output':>10s} {'Cost':>10s}")
    print(f"  {'─' * 30} {'─' * 6} {'─' * 10} {'─' * 10} {'─' * 10}")
    for m in models:
        print(
            f"  {m['model']:<30s} {m['messages']:>6d} {m['tokens']['input']:>10,} "
            f"{m['tokens']['output']:>10,} {m['cost']:>10.4f}"
        )

sessions = d.get("recent_sessions", [])
if sessions:
    print()
    print(f"  {C['frost']}Recent Sessions:{C['reset']}")
    for s in sessions:
        sid = s["session_id"][:12]
        print(f"  {sid}.. {s['messages']:>4d} msgs  {s['last_active']}")
        if s.get("title"):
            print(f"    {s['title']}")
