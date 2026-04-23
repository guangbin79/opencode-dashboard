#!/usr/bin/env python3
"""OpenCode SQLite data access layer.

Queries the OpenCode database and outputs data in TSV (for fzf) or JSON format.

Usage:
    python3 lib/data.py <command> [options]

Commands:
    sessions          List sessions (TSV)
    session-meta      Show session metadata (JSON)
    messages          List messages in a session (TSV)
    message-detail    Show full message with parts (JSON)
    agent-stats       Agent usage statistics (TSV)
    agent-detail      Detailed agent breakdown (JSON)
    todos             List todos (TSV)
    todo-stats        Todo counts by status/priority (JSON)
"""

import argparse
import json
import os
import sqlite3
import sys
import time
from datetime import datetime, timezone


DB_PATH = os.path.expanduser("~/.local/share/opencode/opencode.db")


def get_connection():
    """Get a read-only SQLite connection."""
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA query_only = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.row_factory = sqlite3.Row
    return conn


def ms_to_datetime(epoch_ms):
    """Convert epoch milliseconds to UTC datetime."""
    if not epoch_ms:
        return None
    return datetime.fromtimestamp(epoch_ms / 1000.0, tz=timezone.utc)


def format_datetime(epoch_ms):
    """Format epoch ms to 'YYYY-MM-DD HH:MM' string."""
    dt = ms_to_datetime(epoch_ms)
    if dt is None:
        return ""
    return dt.strftime("%Y-%m-%d %H:%M")


def format_relative_time(epoch_ms):
    """Format epoch ms as human-readable relative time.

    Returns: 'just now', '5m ago', '2h ago', '3d ago', 'Apr 11', '2025-12-20'
    """
    if not epoch_ms:
        return ""
    dt = ms_to_datetime(epoch_ms)
    now = datetime.now(tz=timezone.utc)
    delta = now - dt
    seconds = int(delta.total_seconds())

    if seconds < 60:
        return "just now"
    if seconds < 3600:
        return f"{seconds // 60}m ago"
    if seconds < 86400:
        return f"{seconds // 3600}h ago"
    if seconds < 14 * 86400:
        return f"{seconds // 86400}d ago"
    if dt.year == now.year:
        return dt.strftime("%b %d")
    return dt.strftime("%Y-%m-%d")


def format_tokens(count):
    """Format token count with k suffix for values > 1000."""
    if count is None:
        return "0"
    if count >= 1000:
        return f"{count / 1000:.1f}k"
    return str(count)


def safe_json_loads(text):
    """Safely parse JSON, returning empty dict on failure."""
    if not text:
        return {}
    try:
        return json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return {}


def tsv_escape(value):
    """Escape a value for TSV output (replace tabs/newlines)."""
    s = str(value) if value is not None else ""
    s = s.replace("\t", " ")
    s = s.replace("\n", " ")
    s = s.replace("\r", "")
    return s


def print_tsv_row(fields):
    """Print a single TSV row."""
    print("\t".join(tsv_escape(f) for f in fields))


def cmd_sessions(args):
    """List sessions with message counts and agent lists."""
    conn = get_connection()
    cursor = conn.cursor()

    sort_map = {
        "updated": "s.time_updated DESC",
        "created": "s.time_created DESC",
        "messages": "msg_count DESC",
    }
    order_clause = sort_map.get(args.sort, "s.time_updated DESC")

    where_clauses = []
    params = []

    if args.active:
        where_clauses.append("s.time_archived IS NULL")

    if args.project:
        where_clauses.append("s.project_id = ?")
        params.append(args.project)

    where_sql = ""
    if where_clauses:
        where_sql = "WHERE " + " AND ".join(where_clauses)

    query = f"""
        SELECT
            s.id,
            s.title,
            COALESCE(p.name, '') AS project_name,
            s.directory,
            s.slug,
            s.time_updated,
            s.time_created,
            COUNT(m.id) AS msg_count
        FROM session s
        LEFT JOIN message m ON m.session_id = s.id
        LEFT JOIN project p ON p.id = s.project_id
        {where_sql}
        GROUP BY s.id
        ORDER BY {order_clause}
        LIMIT ?
    """
    params.append(args.limit)
    cursor.execute(query, params)
    rows = cursor.fetchall()

    session_ids = [row["id"] for row in rows]
    agent_map = {}
    if session_ids:
        placeholders = ",".join("?" for _ in session_ids)
        cursor.execute(
            f"""
            SELECT session_id, json_extract(data, '$.agent') AS agent
            FROM message
            WHERE session_id IN ({placeholders})
              AND json_extract(data, '$.agent') IS NOT NULL
            GROUP BY session_id, agent
            """,
            session_ids,
        )
        for row in cursor.fetchall():
            sid = row["session_id"]
            agent_map.setdefault(sid, []).append(row["agent"])

    # Get last message role per session
    last_role_map = {}
    if session_ids:
        placeholders = ",".join("?" for _ in session_ids)
        cursor.execute(
            f"""
            SELECT session_id, json_extract(data, '$.role') AS role
            FROM message
            WHERE id IN (
                SELECT MAX(id) FROM message
                WHERE session_id IN ({placeholders})
                GROUP BY session_id
            )
            """,
            session_ids,
        )
        for row in cursor.fetchall():
            last_role_map[row["session_id"]] = row["role"]

    now_ms = int(time.time() * 1000)
    output_rows = []
    for row in rows:
        sid = row["id"]
        agents = agent_map.get(sid, [])
        agent_str = ",".join(sorted(set(agents)))[:40]
        rel_time = format_relative_time(row["time_updated"])
        project_name = row["project_name"]
        directory = row["directory"]
        if not project_name and directory:
            project_name = os.path.basename(directory.rstrip("/"))
        title = row["title"] or ""
        is_subagent = "1" if "(@" in title else "0"

        last_role = last_role_map.get(sid, "")
        time_updated = row["time_updated"] or 0
        age_ms = now_ms - time_updated

        if last_role == "assistant" and age_ms < 10 * 60 * 1000:
            status = "running"
        elif last_role == "user" and age_ms < 24 * 3600 * 1000:
            status = "waiting"
        else:
            status = "idle"

        output_rows.append(
            (
                project_name,
                row["time_updated"] or 0,
                [
                    sid,
                    title,
                    project_name,
                    directory,
                    row["msg_count"],
                    agent_str,
                    rel_time,
                    row["slug"],
                    is_subagent,
                    status,
                ],
            )
        )

    # Sort by project_name ASC, then time_updated DESC
    output_rows.sort(key=lambda r: (r[0].lower(), -r[1]))
    for _, _, fields in output_rows:
        print_tsv_row(fields)

    conn.close()


def cmd_session_agents(args):
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute(
        """
        SELECT
            json_extract(data, '$.agent') AS agent_name,
            COUNT(*) AS msg_count,
            SUM(COALESCE(json_extract(data, '$.tokens.input'), 0)) AS total_input,
            SUM(COALESCE(json_extract(data, '$.tokens.output'), 0)) AS total_output
        FROM message
        WHERE session_id = ?
          AND json_extract(data, '$.agent') IS NOT NULL
          AND json_extract(data, '$.agent') != ''
        GROUP BY agent_name
        ORDER BY msg_count DESC
        """,
        (args.session_id,),
    )
    agent_rows = cursor.fetchall()

    cursor.execute(
        """
        SELECT json_extract(data, '$.agent') AS agent_name,
               json_extract(data, '$.role') AS role,
               time_updated
        FROM message
        WHERE session_id = ?
          AND id IN (
            SELECT MAX(id) FROM message
            WHERE session_id = ?
              AND json_extract(data, '$.agent') IS NOT NULL
            GROUP BY json_extract(data, '$.agent')
          )
        """,
        (args.session_id, args.session_id),
    )
    last_msg_map = {}
    for row in cursor.fetchall():
        last_msg_map[row["agent_name"]] = (row["role"], row["time_updated"])

    now_ms = int(time.time() * 1000)
    for row in agent_rows:
        agent_name = row["agent_name"]
        msg_count = row["msg_count"]
        total_input = row["total_input"] or 0
        total_output = row["total_output"] or 0

        last_role, last_time = last_msg_map.get(agent_name, ("", 0))
        age_ms = now_ms - (last_time or 0)

        if last_role == "assistant" and age_ms < 10 * 60 * 1000:
            status = "running"
        elif last_role == "user" and age_ms < 24 * 3600 * 1000:
            status = "waiting"
        else:
            status = "idle"

        print_tsv_row(
            [
                agent_name,
                msg_count,
                format_tokens(total_input),
                format_tokens(total_output),
                status,
            ]
        )

    conn.close()


def cmd_session_meta(args):
    """Show detailed metadata for a single session."""
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute(
        """
        SELECT
            s.id, s.title, s.slug, s.directory, s.version,
            s.time_created, s.time_updated, s.time_archived,
            s.share_url, s.summary_additions, s.summary_deletions,
            s.summary_files, s.summary_diffs,
            COALESCE(p.name, '') AS project_name,
            p.worktree AS project_worktree
        FROM session s
        LEFT JOIN project p ON p.id = s.project_id
        WHERE s.id = ?
        """,
        (args.session_id,),
    )
    session = cursor.fetchone()
    if not session:
        print(json.dumps({"error": "session not found"}))
        conn.close()
        return

    cursor.execute(
        "SELECT COUNT(*) FROM message WHERE session_id = ?",
        (args.session_id,),
    )
    msg_count = cursor.fetchone()[0]

    cursor.execute(
        """
        SELECT DISTINCT json_extract(data, '$.agent') AS agent
        FROM message
        WHERE session_id = ? AND json_extract(data, '$.agent') IS NOT NULL
        """,
        (args.session_id,),
    )
    agents = [row[0] for row in cursor.fetchall()]

    cursor.execute(
        """
        SELECT
            SUM(json_extract(data, '$.tokens.input')) AS total_input,
            SUM(json_extract(data, '$.tokens.output')) AS total_output,
            SUM(COALESCE(json_extract(data, '$.cost'), 0)) AS total_cost
        FROM message
        WHERE session_id = ?
        """,
        (args.session_id,),
    )
    token_row = cursor.fetchone()

    result = {
        "id": session["id"],
        "title": session["title"],
        "project": (
            session["project_name"]
            or (
                os.path.basename(session["directory"].rstrip("/"))
                if session["directory"]
                else None
            )
            or session["project_worktree"]
            or ""
        ),
        "directory": session["directory"],
        "slug": session["slug"],
        "version": session["version"],
        "created": format_datetime(session["time_created"]),
        "updated": format_datetime(session["time_updated"]),
        "archived": format_datetime(session["time_archived"])
        if session["time_archived"]
        else None,
        "messages": msg_count,
        "agents": sorted(set(agents)),
        "tokens_total": {
            "input": token_row["total_input"] or 0,
            "output": token_row["total_output"] or 0,
        },
        "cost_total": round(token_row["total_cost"] or 0, 6),
    }
    print(json.dumps(result, indent=2))
    conn.close()


def cmd_messages(args):
    """List messages in a session."""
    conn = get_connection()
    cursor = conn.cursor()

    where_clauses = ["m.session_id = ?"]
    params = [args.session_id]

    if args.agent is not None and args.agent != "":
        where_clauses.append("json_extract(m.data, '$.agent') = ?")
        params.append(args.agent)

    params.append(args.limit)

    query = f"""
        SELECT
            m.id,
            json_extract(m.data, '$.role') AS role,
            COALESCE(json_extract(m.data, '$.agent'), '') AS agent,
            m.time_created,
            COALESCE(json_extract(m.data, '$.tokens.input'), 0) AS tokens_in,
            COALESCE(json_extract(m.data, '$.tokens.output'), 0) AS tokens_out,
            COALESCE(json_extract(m.data, '$.modelID'), '') AS model,
            m.data
        FROM message m
        WHERE {" AND ".join(where_clauses)}
        ORDER BY m.time_created ASC
        LIMIT ?
    """
    cursor.execute(query, params)
    messages = cursor.fetchall()

    msg_ids = [m["id"] for m in messages]
    preview_map = {}
    if msg_ids:
        placeholders = ",".join("?" for _ in msg_ids)
        cursor.execute(
            f"""
            SELECT
                message_id,
                json_extract(data, '$.type') AS ptype,
                json_extract(data, '$.text') AS text_val,
                json_extract(data, '$.tool') AS tool_name
            FROM part
            WHERE message_id IN ({placeholders})
            ORDER BY message_id, time_created ASC
            """,
            msg_ids,
        )
        for row in cursor.fetchall():
            mid = row["message_id"]
            if mid in preview_map:
                continue
            ptype = row["ptype"]
            if ptype == "text" and row["text_val"]:
                preview_map[mid] = row["text_val"]
            elif ptype == "tool" and row["tool_name"]:
                preview_map[mid] = f"tool: {row['tool_name']}"

    for m in messages:
        raw_preview = preview_map.get(m["id"], "")
        if raw_preview:
            preview = raw_preview[:80].replace("\n", " ").replace("\t", " ")
        else:
            preview = ""
        time_str = format_datetime(m["time_created"])
        print_tsv_row(
            [
                m["id"],
                m["role"] or "",
                m["agent"],
                time_str,
                format_tokens(m["tokens_in"]),
                format_tokens(m["tokens_out"]),
                m["model"],
                preview,
            ]
        )

    conn.close()


def cmd_message_detail(args):
    """Show full message data with all parts."""
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute(
        """
        SELECT id, session_id, time_created, time_updated, data
        FROM message
        WHERE id = ?
        """,
        (args.message_id,),
    )
    msg = cursor.fetchone()
    if not msg:
        print(json.dumps({"error": "message not found"}))
        conn.close()
        return

    msg_data = safe_json_loads(msg["data"])
    tokens = msg_data.get("tokens", {})
    time_info = msg_data.get("time", {})

    created_ms = time_info.get("created") or msg["time_created"]
    completed_ms = time_info.get("completed")
    duration_ms = None
    if created_ms and completed_ms:
        duration_ms = completed_ms - created_ms

    cursor.execute(
        """
        SELECT id, data, time_created
        FROM part
        WHERE message_id = ?
        ORDER BY time_created ASC
        """,
        (args.message_id,),
    )
    parts_rows = cursor.fetchall()

    parts = []
    for pr in parts_rows:
        p_data = safe_json_loads(pr["data"])
        ptype = p_data.get("type", "")
        part_entry = {"type": ptype}

        if ptype == "text":
            part_entry["text"] = p_data.get("text", "")
        elif ptype == "reasoning":
            part_entry["text"] = p_data.get("text", "")
        elif ptype == "tool":
            part_entry["tool"] = p_data.get("tool", "")
            state = p_data.get("state", {})
            part_entry["input"] = state.get("input", {})
            output = state.get("output", "")
            if isinstance(output, str) and len(output) > 2000:
                output = output[:2000] + "..."
            part_entry["output"] = output
        elif ptype == "tool-result":
            part_entry["call_id"] = p_data.get("callID", "")
            part_entry["output"] = p_data.get("text", "")
        elif ptype == "step-start":
            part_entry["snapshot"] = p_data.get("snapshot", "")

        parts.append(part_entry)

    result = {
        "id": msg["id"],
        "session_id": msg["session_id"],
        "role": msg_data.get("role", ""),
        "agent": msg_data.get("agent", ""),
        "model": msg_data.get("modelID", ""),
        "provider": msg_data.get("providerID", ""),
        "tokens": {
            "input": tokens.get("input", 0) or 0,
            "output": tokens.get("output", 0) or 0,
            "reasoning": tokens.get("reasoning", 0) or 0,
        },
        "cost": msg_data.get("cost", 0) or 0,
        "time": format_datetime(created_ms),
        "duration_ms": duration_ms,
        "finish": msg_data.get("finish", ""),
        "parts": parts,
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))
    conn.close()


def cmd_agent_stats(args):
    """Show agent usage statistics."""
    conn = get_connection()
    cursor = conn.cursor()

    sort_map = {
        "count": "msg_count DESC",
        "tokens": "total_tokens DESC",
        "name": "agent_name ASC",
    }
    order_clause = sort_map.get(args.sort, "msg_count DESC")

    cursor.execute(
        f"""
        SELECT
            json_extract(data, '$.agent') AS agent_name,
            COUNT(*) AS msg_count,
            SUM(COALESCE(json_extract(data, '$.tokens.input'), 0)) AS total_input,
            SUM(COALESCE(json_extract(data, '$.tokens.output'), 0)) AS total_output,
            COUNT(DISTINCT session_id) AS sessions_count
        FROM message
        WHERE json_extract(data, '$.agent') IS NOT NULL
        GROUP BY agent_name
        ORDER BY {order_clause}
        """
    )
    rows = cursor.fetchall()

    for row in rows:
        total_in = row["total_input"] or 0
        total_out = row["total_output"] or 0
        count = row["msg_count"]
        avg = int((total_in + total_out) / count) if count > 0 else 0

        print_tsv_row(
            [
                row["agent_name"],
                row["msg_count"],
                format_tokens(total_in),
                format_tokens(total_out),
                format_tokens(avg),
                row["sessions_count"],
            ]
        )

    conn.close()


def cmd_agent_detail(args):
    """Show detailed breakdown for a specific agent."""
    conn = get_connection()
    cursor = conn.cursor()
    agent_name = args.agent_name

    cursor.execute(
        """
        SELECT
            COUNT(*) AS msg_count,
            SUM(COALESCE(json_extract(data, '$.tokens.input'), 0)) AS total_input,
            SUM(COALESCE(json_extract(data, '$.tokens.output'), 0)) AS total_output,
            SUM(COALESCE(json_extract(data, '$.tokens.reasoning'), 0)) AS total_reasoning,
            SUM(COALESCE(json_extract(data, '$.cost'), 0)) AS total_cost,
            COUNT(DISTINCT session_id) AS sessions_count
        FROM message
        WHERE json_extract(data, '$.agent') = ?
        """,
        (agent_name,),
    )
    overall = cursor.fetchone()
    if not overall or overall["msg_count"] == 0:
        print(json.dumps({"error": f"agent '{agent_name}' not found"}))
        conn.close()
        return

    cursor.execute(
        """
        SELECT
            COALESCE(json_extract(data, '$.modelID'), 'unknown') AS model,
            COUNT(*) AS msg_count,
            SUM(COALESCE(json_extract(data, '$.tokens.input'), 0)) AS total_input,
            SUM(COALESCE(json_extract(data, '$.tokens.output'), 0)) AS total_output,
            SUM(COALESCE(json_extract(data, '$.cost'), 0)) AS total_cost
        FROM message
        WHERE json_extract(data, '$.agent') = ?
        GROUP BY model
        ORDER BY msg_count DESC
        """,
        (agent_name,),
    )
    by_model = []
    for row in cursor.fetchall():
        by_model.append(
            {
                "model": row["model"],
                "messages": row["msg_count"],
                "tokens": {
                    "input": row["total_input"] or 0,
                    "output": row["total_output"] or 0,
                },
                "cost": round(row["total_cost"] or 0, 6),
            }
        )

    cursor.execute(
        """
        SELECT
            m.session_id,
            s.title,
            COUNT(*) AS msg_count,
            MAX(m.time_created) AS last_active
        FROM message m
        LEFT JOIN session s ON s.id = m.session_id
        WHERE json_extract(m.data, '$.agent') = ?
        GROUP BY m.session_id
        ORDER BY last_active DESC
        LIMIT 10
        """,
        (agent_name,),
    )
    recent_sessions = []
    for row in cursor.fetchall():
        recent_sessions.append(
            {
                "session_id": row["session_id"],
                "title": row["title"] or "",
                "messages": row["msg_count"],
                "last_active": format_datetime(row["last_active"]),
            }
        )

    result = {
        "agent": agent_name,
        "messages": overall["msg_count"],
        "sessions": overall["sessions_count"],
        "tokens": {
            "input": overall["total_input"] or 0,
            "output": overall["total_output"] or 0,
            "reasoning": overall["total_reasoning"] or 0,
        },
        "cost": round(overall["total_cost"] or 0, 6),
        "by_model": by_model,
        "recent_sessions": recent_sessions,
    }
    print(json.dumps(result, indent=2))
    conn.close()


def cmd_todos(args):
    """List todos with optional filtering."""
    conn = get_connection()
    cursor = conn.cursor()

    where_clauses = []
    params = []

    if args.status and args.status != "all":
        where_clauses.append("t.status = ?")
        params.append(args.status)

    if args.session:
        where_clauses.append("t.session_id = ?")
        params.append(args.session)

    where_sql = ""
    if where_clauses:
        where_sql = "WHERE " + " AND ".join(where_clauses)

    cursor.execute(
        f"""
        SELECT
            t.session_id,
            t.status,
            t.priority,
            t.content,
            t.position,
            t.time_created,
            COALESCE(s.title, '') AS session_title
        FROM todo t
        LEFT JOIN session s ON s.id = t.session_id
        {where_sql}
        ORDER BY
            CASE t.status
                WHEN 'in_progress' THEN 0
                WHEN 'pending' THEN 1
                WHEN 'completed' THEN 2
                WHEN 'cancelled' THEN 3
                ELSE 4
            END,
            t.position ASC
        """,
        params,
    )
    rows = cursor.fetchall()

    for row in rows:
        rel_time = format_relative_time(row["time_created"])
        print_tsv_row(
            [
                row["session_id"],
                row["status"],
                row["priority"],
                row["content"],
                row["session_title"],
                row["position"],
                rel_time,
            ]
        )

    conn.close()


def cmd_todo_stats(args):
    """Show todo counts by status and priority."""
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute(
        """
        SELECT status, COUNT(*) AS cnt
        FROM todo
        GROUP BY status
        ORDER BY
            CASE status
                WHEN 'in_progress' THEN 0
                WHEN 'pending' THEN 1
                WHEN 'completed' THEN 2
                WHEN 'cancelled' THEN 3
                ELSE 4
            END
        """
    )
    by_status = {}
    for row in cursor.fetchall():
        by_status[row["status"]] = row["cnt"]

    cursor.execute(
        """
        SELECT priority, COUNT(*) AS cnt
        FROM todo
        GROUP BY priority
        ORDER BY
            CASE priority
                WHEN 'high' THEN 0
                WHEN 'medium' THEN 1
                WHEN 'low' THEN 2
                ELSE 3
            END
        """
    )
    by_priority = {}
    for row in cursor.fetchall():
        by_priority[row["priority"]] = row["cnt"]

    cursor.execute(
        """
        SELECT status, priority, COUNT(*) AS cnt
        FROM todo
        GROUP BY status, priority
        ORDER BY status, priority
        """
    )
    breakdown = []
    for row in cursor.fetchall():
        breakdown.append(
            {
                "status": row["status"],
                "priority": row["priority"],
                "count": row["cnt"],
            }
        )

    cursor.execute("SELECT COUNT(*) FROM todo")
    total = cursor.fetchone()[0]

    result = {
        "total": total,
        "by_status": by_status,
        "by_priority": by_priority,
        "breakdown": breakdown,
    }
    print(json.dumps(result, indent=2))
    conn.close()


def cmd_project_stats(args):
    """List projects with session counts and status."""
    conn = get_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT
            s.id, s.title, s.directory, s.time_updated,
            COALESCE(NULLIF(p.name, ''), '') AS project_name
        FROM session s
        LEFT JOIN project p ON p.id = s.project_id
        WHERE s.time_archived IS NULL
        ORDER BY s.time_updated DESC
    """)
    rows = cursor.fetchall()

    now_ms = int(time.time() * 1000)

    from collections import OrderedDict

    projects = OrderedDict()
    for row in rows:
        pn = row["project_name"]
        if not pn:
            pn = (
                os.path.basename(row["directory"].rstrip("/"))
                if row["directory"]
                else "unknown"
            )
        title = row["title"] or ""
        is_sub = "(@" in title
        if is_sub:
            continue

        if pn not in projects:
            projects[pn] = {
                "name": pn,
                "count": 0,
                "updated": 0,
                "running": 0,
                "waiting": 0,
                "latest_title": "",
            }
        p = projects[pn]
        p["count"] += 1
        if row["time_updated"] and row["time_updated"] > p["updated"]:
            p["updated"] = row["time_updated"]
            p["latest_title"] = title

    # Get last role for each session to compute running/waiting
    session_ids = [row["id"] for row in rows]
    last_role_map = {}
    if session_ids:
        placeholders = ",".join("?" for _ in session_ids)
        cursor.execute(
            f"""
            SELECT session_id, json_extract(data, '$.role') AS role
            FROM message
            WHERE id IN (
                SELECT MAX(id) FROM message
                WHERE session_id IN ({placeholders})
                GROUP BY session_id
            )
            """,
            session_ids,
        )
        for row in cursor.fetchall():
            last_role_map[row["session_id"]] = row["role"]

    for row in rows:
        pn = row["project_name"]
        if not pn:
            pn = (
                os.path.basename(row["directory"].rstrip("/"))
                if row["directory"]
                else "unknown"
            )
        title = row["title"] or ""
        if "(@" in title:
            continue
        if pn not in projects:
            continue
        last_role = last_role_map.get(row["id"], "")
        age_ms = now_ms - (row["time_updated"] or 0)
        if last_role == "assistant" and age_ms < 10 * 60 * 1000:
            projects[pn]["running"] += 1
        elif last_role == "user" and age_ms < 24 * 3600 * 1000:
            projects[pn]["waiting"] += 1

    # Sort by updated DESC
    sorted_projects = sorted(
        projects.values(), key=lambda p: p["updated"], reverse=True
    )
    for p in sorted_projects:
        rel_time = format_relative_time(p["updated"])
        print_tsv_row(
            [
                p["name"],
                p["count"],
                p["running"],
                p["waiting"],
                rel_time,
                p["latest_title"][:60],
            ]
        )

    conn.close()


def cmd_message_count(args):
    """Get message count for a session."""
    conn = get_connection()
    cursor = conn.cursor()

    where_clauses = ["session_id = ?"]
    params = [args.session_id]

    if args.agent is not None and args.agent != "":
        where_clauses.append("json_extract(data, '$.agent') = ?")
        params.append(args.agent)

    query = f"SELECT COUNT(*) FROM message WHERE {' AND '.join(where_clauses)}"
    cursor.execute(query, params)
    count = cursor.fetchone()[0]
    print(count)
    conn.close()


def cmd_agent_status(args):
    """Get agent status for a session."""
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT json_extract(data, '$.role') AS role,
               json_extract(data, '$.agent') AS agent,
               time_updated
        FROM message
        WHERE session_id = ?
        ORDER BY time_updated DESC
        LIMIT 1
        """,
        (args.session_id,),
    )
    row = cursor.fetchone()
    if not row:
        print(json.dumps({"status": "idle", "agent": "", "role": ""}))
        conn.close()
        return
    now_ms = int(time.time() * 1000)
    age_ms = now_ms - (row["time_updated"] or 0)
    status = "idle"
    if row["role"] == "assistant" and age_ms < 10 * 60 * 1000:
        status = "running"
    elif row["role"] == "user" and age_ms < 24 * 3600 * 1000:
        status = "waiting"
    result = {
        "status": status,
        "agent": row["agent"] or "",
        "role": row["role"] or "",
        "last_updated": row["time_updated"],
    }
    print(json.dumps(result))
    conn.close()


def build_parser():
    """Build the argument parser with subcommands."""
    parser = argparse.ArgumentParser(
        prog="data.py",
        description="OpenCode SQLite data access layer",
    )
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    p_sessions = subparsers.add_parser("sessions", help="List sessions")
    p_sessions.add_argument(
        "--limit", type=int, default=50, help="Max results (default: 50)"
    )
    p_sessions.add_argument(
        "--project", type=str, default=None, help="Filter by project ID"
    )
    p_sessions.add_argument(
        "--active", action="store_true", help="Only active (non-archived) sessions"
    )
    p_sessions.add_argument(
        "--sort",
        choices=["updated", "created", "messages"],
        default="updated",
        help="Sort order (default: updated)",
    )

    p_meta = subparsers.add_parser("session-meta", help="Session metadata")
    p_meta.add_argument("session_id", type=str, help="Session ID")

    p_sagents = subparsers.add_parser("session-agents", help="List agents in a session")
    p_sagents.add_argument("session_id", type=str, help="Session ID")

    p_msgs = subparsers.add_parser("messages", help="List messages in a session")
    p_msgs.add_argument("session_id", type=str, help="Session ID")
    p_msgs.add_argument(
        "--limit", type=int, default=200, help="Max results (default: 200)"
    )
    p_msgs.add_argument(
        "--agent", type=str, default=None, help="Filter by agent name"
    )

    p_msgd = subparsers.add_parser("message-detail", help="Full message with parts")
    p_msgd.add_argument("message_id", type=str, help="Message ID")

    p_astats = subparsers.add_parser("agent-stats", help="Agent usage statistics")
    p_astats.add_argument(
        "--sort",
        choices=["count", "tokens", "name"],
        default="count",
        help="Sort order (default: count)",
    )

    p_adetail = subparsers.add_parser("agent-detail", help="Detailed agent breakdown")
    p_adetail.add_argument("agent_name", type=str, help="Agent name")

    p_todos = subparsers.add_parser("todos", help="List todos")
    p_todos.add_argument(
        "--status",
        choices=["all", "pending", "in_progress", "completed"],
        default="all",
        help="Filter by status (default: all)",
    )
    p_todos.add_argument(
        "--session", type=str, default=None, help="Filter by session ID"
    )

    subparsers.add_parser("todo-stats", help="Todo counts by status and priority")

    subparsers.add_parser(
        "project-stats", help="Project list with session counts"
    )

    p_count = subparsers.add_parser("message-count", help="Message count for session")
    p_count.add_argument("session_id", type=str, help="Session ID")
    p_count.add_argument(
        "--agent", type=str, default=None, help="Filter by agent name"
    )

    p_status = subparsers.add_parser("agent-status", help="Agent status for session")
    p_status.add_argument("session_id", type=str, help="Session ID")

    return parser


def main():
    """Main entry point."""
    parser = build_parser()
    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    command_map = {
        "sessions": cmd_sessions,
        "session-meta": cmd_session_meta,
        "session-agents": cmd_session_agents,
        "messages": cmd_messages,
        "message-detail": cmd_message_detail,
        "agent-stats": cmd_agent_stats,
        "agent-detail": cmd_agent_detail,
        "todos": cmd_todos,
        "todo-stats": cmd_todo_stats,
        "project-stats": cmd_project_stats,
        "message-count": cmd_message_count,
        "agent-status": cmd_agent_status,
    }

    handler = command_map.get(args.command)
    if handler:
        handler(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
