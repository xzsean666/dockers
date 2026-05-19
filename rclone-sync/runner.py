#!/usr/bin/env python3
import argparse
import contextlib
import datetime as dt
import fcntl
import json
import os
import re
import shlex
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

try:
    from zoneinfo import ZoneInfo
except Exception:  # pragma: no cover
    ZoneInfo = None

try:
    import yaml
except Exception:  # pragma: no cover
    yaml = None


VERSION = "0.1.0"
DESTRUCTIVE_MODES = {"mirror", "archive", "prune"}
TRANSFER_MODES = {"copy", "mirror", "archive"}
VALID_MODES = {"copy", "mirror", "archive", "prune", "check"}


class ConfigError(Exception):
    pass


class SlackNotifier:
    DEFAULT_EVENTS = {
        "startup",
        "job_start",
        "job_success",
        "job_error",
        "task_start",
        "task_success",
        "task_error",
    }

    def __init__(
        self,
        webhook_url: str,
        events: Iterable[str],
        run_id: str,
        timeout: int = 10,
        username: str = "",
        channel: str = "",
    ):
        self.webhook_url = webhook_url.strip()
        self.events = {event.strip().lower() for event in events if event.strip()}
        self.run_id = run_id
        self.timeout = max(1, timeout)
        self.username = username.strip()
        self.channel = channel.strip()

    @classmethod
    def from_env(cls, env: Dict[str, str], run_id: str) -> "SlackNotifier":
        webhook_url = (env.get("RCLONE_SYNC_SLACK_WEBHOOK_URL") or env.get("SLACK_WEBHOOK_URL") or "").strip()
        raw_events = env.get("RCLONE_SYNC_SLACK_EVENTS", "")
        events = split_list(raw_events) if raw_events.strip() else sorted(cls.DEFAULT_EVENTS)
        if any(event.lower() == "all" for event in events):
            events = sorted(cls.DEFAULT_EVENTS | {"run_start", "run_success", "run_error"})
        timeout = env_int("RCLONE_SYNC_SLACK_TIMEOUT", 10)
        return cls(
            webhook_url=webhook_url,
            events=events,
            run_id=run_id,
            timeout=timeout,
            username=env.get("RCLONE_SYNC_SLACK_USERNAME", "rclone-sync"),
            channel=env.get("RCLONE_SYNC_SLACK_CHANNEL", ""),
        )

    def enabled_for(self, event: str) -> bool:
        if not self.webhook_url:
            return False
        if "none" in self.events or "false" in self.events or "off" in self.events:
            return False
        return event.lower() in self.events or "all" in self.events

    def send(self, event: str, title: str, fields: Dict[str, Any], level: str = "INFO") -> None:
        if not self.enabled_for(event):
            return
        payload: Dict[str, Any] = {"text": self.format_message(event, title, fields, level)}
        if self.username:
            payload["username"] = self.username
        if self.channel:
            payload["channel"] = self.channel
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        request = urllib.request.Request(
            self.webhook_url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                response.read()
            log(f"Slack notification sent event={event}")
        except Exception as exc:
            log(f"Slack notification failed event={event}: {exc}", level="ERROR")

    def format_message(self, event: str, title: str, fields: Dict[str, Any], level: str) -> str:
        status = "ERROR" if level == "ERROR" else "INFO"
        lines = [f"*{title}*", f"event: `{event}` status: `{status}`"]
        for key, value in fields.items():
            if value in (None, ""):
                continue
            lines.append(f"{key}: `{format_slack_value(value)}`")
        return "\n".join(lines)


class RcloneSync:
    def __init__(self, config_path: str):
        self.config_path = config_path
        self.env = os.environ
        self.rclone_bin = self.env.get("RCLONE_SYNC_RCLONE_BIN", "rclone")
        self.flag_cache: Dict[Tuple[str, str], bool] = {}
        self.run_started = now_local(self.env.get("TZ", "UTC"))
        self.run_id = self.run_started.strftime("%Y%m%d_%H%M%S")
        self.notifier = SlackNotifier.from_env(self.env, self.run_id)

    def run(self, only_job: Optional[str] = None) -> int:
        self.map_provider_envs()
        config = self.load_config()
        jobs = [j for j in config.get("jobs", []) if j.get("enabled", True)]
        if only_job:
            jobs = [j for j in jobs if j.get("name") == only_job]
        if not jobs:
            log("No enabled jobs to run")
            return 0

        errors = 0
        for job in jobs:
            try:
                self.run_job(config, job)
            except Exception as exc:
                errors += 1
                self.notifier.send(
                    "job_error",
                    "rclone-sync job failed",
                    {
                        "job": str(job.get("name", "<unnamed>")),
                        "run_id": self.run_id,
                        "error": str(exc),
                    },
                    level="ERROR",
                )
                log(f"ERROR job={job.get('name', '<unnamed>')}: {exc}", level="ERROR")
        return 1 if errors else 0

    def notify_startup(self) -> None:
        source_root = self.env.get("RCLONE_SYNC_SOURCE_ROOT", "").strip() or self.root_from_parts("SOURCE", "src")
        target_root = self.env.get("RCLONE_SYNC_TARGET_ROOT", "").strip() or self.root_from_parts("TARGET", "dst")
        mode = self.env.get("RCLONE_SYNC_MODE") or inferred_mode_from_env(self.env)
        job_count: Any = "env-only"
        try:
            config = self.load_config()
            jobs = [j for j in config.get("jobs", []) if j.get("enabled", True)]
            job_count = len(jobs)
            if jobs:
                first = deep_merge(config.get("defaults", {}) or {}, jobs[0])
                source_root = str(first.get("source_root") or source_root)
                target_root = str(first.get("target_root") or target_root)
                mode = normalize_mode(first.get("operation", mode))
        except Exception as exc:
            job_count = f"config error: {exc}"
        fields = {
            "version": VERSION,
            "host": socket.gethostname(),
            "run_id": self.run_id,
            "schedule": self.env.get("RCLONE_SYNC_SCHEDULE") or self.env.get("CRON_SCHEDULE") or "run-once",
            "run_on_startup": self.env.get("RCLONE_SYNC_RUN_ON_STARTUP", "true"),
            "jobs": job_count,
            "mode": mode,
            "dry_run": self.env.get("RCLONE_SYNC_DRY_RUN", "true"),
            "source": source_root or "<unset>",
            "target": target_root or "<unset>",
        }
        self.notifier.send("startup", "rclone-sync container started", fields)

    def load_config(self) -> Dict[str, Any]:
        path = Path(self.config_path) if self.config_path else None
        if path and path.exists():
            if yaml is None:
                raise ConfigError("YAML config requires PyYAML. Install py3-yaml or use env-only mode.")
            with path.open("r", encoding="utf-8") as fh:
                data = yaml.safe_load(fh) or {}
            if not isinstance(data, dict):
                raise ConfigError("YAML config root must be an object")
            return data
        return self.config_from_env()

    def config_from_env(self) -> Dict[str, Any]:
        mode = self.env.get("RCLONE_SYNC_MODE", "").strip().lower()
        delete_source = env_bool("RCLONE_SYNC_DELETE_SOURCE", False)
        delete_target_extras = env_bool("RCLONE_SYNC_DELETE_TARGET_EXTRAS", False)
        if not mode:
            if delete_source and delete_target_extras:
                raise ConfigError(
                    "RCLONE_SYNC_DELETE_SOURCE and RCLONE_SYNC_DELETE_TARGET_EXTRAS cannot both be true; use RCLONE_SYNC_MODE"
                )
            if delete_source:
                mode = "archive"
            elif delete_target_extras:
                mode = "mirror"
            else:
                mode = "copy"

        source_root = self.env.get("RCLONE_SYNC_SOURCE_ROOT", "").strip() or self.root_from_parts("SOURCE", "src")
        target_root = self.env.get("RCLONE_SYNC_TARGET_ROOT", "").strip() or self.root_from_parts("TARGET", "dst")
        directories = split_list(self.env.get("RCLONE_SYNC_DIRECTORIES", ".")) or ["."]

        filters = {
            "include": split_list(self.env.get("RCLONE_SYNC_INCLUDE", "")),
            "exclude": split_list(self.env.get("RCLONE_SYNC_EXCLUDE", "")),
            "exclude_extensions": split_list(self.env.get("RCLONE_SYNC_EXCLUDE_EXTENSIONS", "")),
            "exclude_from": split_list(self.env.get("RCLONE_SYNC_EXCLUDE_FROM", "")),
            "filter_from": split_list(self.env.get("RCLONE_SYNC_FILTER_FROM", "")),
            "files_from": split_list(self.env.get("RCLONE_SYNC_FILES_FROM", "")),
            "exclude_if_present": split_list(self.env.get("RCLONE_SYNC_EXCLUDE_IF_PRESENT", "")),
        }
        filters = {k: v for k, v in filters.items() if v}

        age = {}
        if self.env.get("RCLONE_SYNC_OLDER_THAN", "").strip():
            age["older_than"] = self.env["RCLONE_SYNC_OLDER_THAN"].strip()
        if self.env.get("RCLONE_SYNC_NEWER_THAN", "").strip():
            age["newer_than"] = self.env["RCLONE_SYNC_NEWER_THAN"].strip()

        date_filter = {}
        if self.env.get("RCLONE_SYNC_DATE_BEFORE", "").strip():
            date_filter["before"] = self.env["RCLONE_SYNC_DATE_BEFORE"].strip()
        if self.env.get("RCLONE_SYNC_DATE_AFTER", "").strip():
            date_filter["after"] = self.env["RCLONE_SYNC_DATE_AFTER"].strip()

        allow_unlimited_delete = env_bool("RCLONE_SYNC_ALLOW_UNLIMITED_DELETE", False)
        safety = {
            "dry_run": env_bool("RCLONE_SYNC_DRY_RUN", True),
            "max_delete": env_int("RCLONE_SYNC_MAX_DELETE", -1 if allow_unlimited_delete else 1000),
            "max_delete_size": self.env.get("RCLONE_SYNC_MAX_DELETE_SIZE", "" if allow_unlimited_delete else "100G"),
            "allow_delete_excluded": env_bool("RCLONE_SYNC_ALLOW_DELETE_EXCLUDED", False),
            "allow_root_path": env_bool("RCLONE_SYNC_ALLOW_ROOT_PATH", False),
            "allow_all_source_move": env_bool("RCLONE_SYNC_ALLOW_ALL_SOURCE_MOVE", False),
            "allow_unlimited_delete": allow_unlimited_delete,
        }

        global_config = {
            "timezone": self.env.get("TZ", "UTC"),
            "rclone_config": self.env.get("RCLONE_SYNC_RCLONE_CONFIG", self.env.get("RCLONE_CONFIG", "")),
            "log_level": self.env.get("RCLONE_SYNC_LOG_LEVEL", "INFO"),
            "stats": self.env.get("RCLONE_SYNC_STATS", "30s"),
            "transfers": env_int("RCLONE_SYNC_TRANSFERS", 4),
            "checkers": env_int("RCLONE_SYNC_CHECKERS", 8),
            "retries": env_int("RCLONE_SYNC_RETRIES", 3),
            "low_level_retries": env_int("RCLONE_SYNC_LOW_LEVEL_RETRIES", 10),
            "logs_dir": self.env.get("RCLONE_SYNC_LOGS_DIR", "/logs"),
            "state_dir": self.env.get("RCLONE_SYNC_STATE_DIR", "/state"),
        }

        job = {
            "name": self.env.get("RCLONE_SYNC_JOB_NAME", "env-job"),
            "enabled": True,
            "operation": mode,
            "source_root": source_root,
            "target_root": target_root,
            "directories": directories,
            "filters": filters,
            "age": age,
            "date": date_filter,
            "safety": safety,
            "archive": {"delete_empty_source_dirs": env_bool("RCLONE_SYNC_DELETE_EMPTY_SOURCE_DIRS", True)},
            "prune": {"rmdirs": env_bool("RCLONE_SYNC_RMDIRS", True)},
        }
        return {"version": 1, "global": global_config, "defaults": {}, "jobs": [job]}

    def root_from_parts(self, side: str, default_remote: str) -> str:
        remote = self.env.get(f"RCLONE_SYNC_{side}_REMOTE", default_remote).strip()
        bucket = self.env.get(f"RCLONE_SYNC_{side}_BUCKET", "").strip().strip("/")
        path = self.env.get(f"RCLONE_SYNC_{side}_PATH", "").strip().strip("/")
        if not bucket and not path:
            return ""
        if bucket and path:
            return f"{remote}:{bucket}/{path}"
        if bucket:
            return f"{remote}:{bucket}"
        return f"{remote}:{path}"

    def map_provider_envs(self) -> None:
        source_root = self.env.get("RCLONE_SYNC_SOURCE_ROOT", "").strip() or self.root_from_parts("SOURCE", "src")
        target_root = self.env.get("RCLONE_SYNC_TARGET_ROOT", "").strip() or self.root_from_parts("TARGET", "dst")
        self.map_config_prefix("RCLONE_SYNC_SOURCE_CONFIG_", source_root, fallback_remote="SRC")
        self.map_config_prefix("RCLONE_SYNC_TARGET_CONFIG_", target_root, fallback_remote="DST")

    def map_config_prefix(self, prefix: str, root: str, fallback_remote: str) -> None:
        remote = remote_name(root) or fallback_remote
        remote_env = sanitize_env_name(remote)
        token_parts: Dict[str, str] = {}
        for key, value in list(self.env.items()):
            if not key.startswith(prefix):
                continue
            suffix = key[len(prefix):]
            if not suffix:
                continue
            if suffix.upper().startswith("TOKEN_"):
                token_parts[suffix.upper()[len("TOKEN_"):]] = value
                continue
            target = f"RCLONE_CONFIG_{remote_env}_{suffix.upper()}"
            if target not in os.environ:
                os.environ[target] = value
        self.maybe_build_oauth_token_env(remote_env, token_parts)

    def maybe_build_oauth_token_env(self, remote_env: str, token_parts: Dict[str, str]) -> None:
        if not token_parts:
            return
        target = f"RCLONE_CONFIG_{remote_env}_TOKEN"
        if target in os.environ:
            return
        refresh_token = token_parts.get("REFRESH_TOKEN") or token_parts.get("REFRESH")
        access_token = token_parts.get("ACCESS_TOKEN") or token_parts.get("ACCESS") or ""
        if not refresh_token:
            raise ConfigError(
                f"{target} was not set and TOKEN_REFRESH_TOKEN is missing; Google Drive OAuth needs a refresh token"
            )
        token = {
            "access_token": access_token,
            "token_type": token_parts.get("TOKEN_TYPE") or token_parts.get("TYPE") or "Bearer",
            "refresh_token": refresh_token,
            "expiry": token_parts.get("EXPIRY") or token_parts.get("EXPIRES_AT") or "2000-01-01T00:00:00Z",
        }
        os.environ[target] = json.dumps(token, separators=(",", ":"))

    def run_job(self, config: Dict[str, Any], job: Dict[str, Any]) -> None:
        global_config = config.get("global", {}) or {}
        defaults = config.get("defaults", {}) or {}
        job = deep_merge(defaults, job)
        job_name = require_name(job)
        operation = normalize_mode(job.get("operation", "copy"))
        dry_run = get_nested_bool(job, ["safety", "dry_run"], global_config.get("dry_run_default", True))

        logs_dir = Path(global_config.get("logs_dir") or self.env.get("RCLONE_SYNC_LOGS_DIR", "/logs"))
        state_dir = Path(global_config.get("state_dir") or self.env.get("RCLONE_SYNC_STATE_DIR", "/state"))
        run_dir = logs_dir / "runs" / self.run_id / safe_filename(job_name)
        run_dir.mkdir(parents=True, exist_ok=True)
        (state_dir / "locks").mkdir(parents=True, exist_ok=True)

        with self.job_lock(state_dir, job_name):
            tasks = self.expand_tasks(job)
            log(f"Starting job={job_name} mode={operation} tasks={len(tasks)} dry_run={dry_run}")
            self.notifier.send(
                "job_start",
                "rclone-sync job started",
                {
                    "job": job_name,
                    "run_id": self.run_id,
                    "mode": operation,
                    "dry_run": dry_run,
                    "tasks": len(tasks),
                    "source_root": job.get("source_root", ""),
                    "target_root": job.get("target_root", ""),
                    "directories": ", ".join(str(t["directory"]) for t in tasks),
                },
            )
            for idx, task in enumerate(tasks, start=1):
                task_name = f"{idx:03d}-{safe_filename(task['directory'])}"
                task_dir = run_dir / task_name
                task_dir.mkdir(parents=True, exist_ok=True)
                self.run_task(global_config, job, task, task_dir)
            log(f"Finished job={job_name}")
            self.notifier.send(
                "job_success",
                "rclone-sync job finished",
                {
                    "job": job_name,
                    "run_id": self.run_id,
                    "mode": operation,
                    "tasks": len(tasks),
                    "dry_run": dry_run,
                },
            )

    @contextlib.contextmanager
    def job_lock(self, state_dir: Path, job_name: str):
        lock_path = state_dir / "locks" / f"{safe_filename(job_name)}.lock"
        with lock_path.open("w", encoding="utf-8") as fh:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ConfigError(f"job {job_name!r} is already running")
            fh.write(f"{os.getpid()}\n")
            fh.flush()
            try:
                yield
            finally:
                fcntl.flock(fh, fcntl.LOCK_UN)

    def expand_tasks(self, job: Dict[str, Any]) -> List[Dict[str, Any]]:
        operation = normalize_mode(job.get("operation", "copy"))
        source_root = str(job.get("source_root") or "").strip()
        target_root = str(job.get("target_root") or "").strip()
        safety = job.get("safety", {}) or {}
        allow_root = bool(safety.get("allow_root_path", False))

        if not source_root:
            raise ConfigError("source_root is required")
        if operation != "prune" and not target_root:
            raise ConfigError("target_root is required unless operation=prune")
        validate_root(source_root, "source_root", allow_root)
        if target_root:
            validate_root(target_root, "target_root", allow_root)
        if target_root and safety.get("deny_overlapping_paths", True):
            validate_no_overlap(source_root, target_root)

        directories = job.get("directories", ["."])
        if isinstance(directories, str):
            directories = split_list(directories) or ["."]
        if not isinstance(directories, list) or not directories:
            raise ConfigError("directories must be a non-empty list or CSV string")

        tasks = []
        for item in directories:
            item_overrides: Dict[str, Any] = {}
            if isinstance(item, dict):
                forbidden = {"target", "target_path", "to", "dest", "destination"}
                bad = forbidden.intersection(item.keys())
                if bad:
                    raise ConfigError(f"directory item cannot set target path fields: {', '.join(sorted(bad))}")
                directory = str(item.get("path", "")).strip()
                item_overrides = {k: v for k, v in item.items() if k != "path"}
            else:
                directory = str(item).strip()
            directory = normalize_directory(directory)
            source_path = join_rclone_path(source_root, directory)
            target_path = join_rclone_path(target_root, directory) if target_root else ""
            merged = deep_merge(job, item_overrides)
            tasks.append({
                "directory": directory,
                "source_path": source_path,
                "target_path": target_path,
                "config": merged,
            })
        return tasks

    def run_task(self, global_config: Dict[str, Any], job: Dict[str, Any], task: Dict[str, Any], task_dir: Path) -> None:
        cfg = task["config"]
        operation = normalize_mode(cfg.get("operation", "copy"))
        dry_run = get_nested_bool(cfg, ["safety", "dry_run"], global_config.get("dry_run_default", True))
        started = time.monotonic()
        preflight: Optional[Dict[str, Any]] = None
        self.notifier.send(
            "task_start",
            "rclone-sync task started",
            {
                "job": require_name(job),
                "run_id": self.run_id,
                "directory": task["directory"],
                "mode": operation,
                "dry_run": dry_run,
                "source": task["source_path"],
                "target": task["target_path"] or "<none>",
            },
        )
        try:
            self.validate_task(global_config, cfg, task, dry_run)

            if operation in {"archive", "prune"}:
                preflight = self.preflight_source_delete(global_config, cfg, task, dry_run)

            argv = self.build_rclone_command(global_config, cfg, task, task_dir, dry_run)
            write_json(task_dir / "command.json", {"argv": argv, "dry_run": dry_run, "directory": task["directory"]})
            log(f"Running task directory={task['directory']} command={shell_join_masked(argv)}")
            result = subprocess.run(argv, text=True)
            write_json(task_dir / "result.json", {"returncode": result.returncode})
            if result.returncode != 0:
                raise RuntimeError(f"rclone exited with code {result.returncode} for directory={task['directory']}")
        except Exception as exc:
            self.notifier.send(
                "task_error",
                "rclone-sync task failed",
                task_result_fields(job, task, operation, dry_run, self.run_id, started, preflight, error=str(exc)),
                level="ERROR",
            )
            raise

        self.notifier.send(
            "task_success",
            "rclone-sync task finished",
            task_result_fields(job, task, operation, dry_run, self.run_id, started, preflight),
        )

    def validate_task(self, global_config: Dict[str, Any], cfg: Dict[str, Any], task: Dict[str, Any], dry_run: bool) -> None:
        operation = normalize_mode(cfg.get("operation", "copy"))
        if operation not in VALID_MODES:
            raise ConfigError(f"unsupported operation: {operation}")

        safety = cfg.get("safety", {}) or {}
        allow_destructive = env_bool("RCLONE_SYNC_ALLOW_DESTRUCTIVE", False)
        allow_unlimited_delete = bool(safety.get("allow_unlimited_delete", False))
        max_delete = normalize_delete_limit(safety.get("max_delete"), "max_delete", allow_unlimited_delete)
        max_delete_size = normalize_delete_size(safety.get("max_delete_size"), "max_delete_size", allow_unlimited_delete)
        safety["max_delete"] = max_delete
        safety["max_delete_size"] = max_delete_size

        age_flags = self.resolve_age_flags(global_config, cfg)
        has_time_filter = bool(age_flags.get("min_age") or age_flags.get("max_age"))
        filters = cfg.get("filters", {}) or {}
        has_filter = any(filters.get(k) for k in ("include", "exclude", "exclude_extensions", "exclude_from", "filter_from", "files_from"))

        if operation in DESTRUCTIVE_MODES and not dry_run and not allow_destructive:
            raise ConfigError(
                f"operation={operation} can delete data; set RCLONE_SYNC_ALLOW_DESTRUCTIVE=true and RCLONE_SYNC_DRY_RUN=false"
            )
        if operation == "mirror" and not allow_unlimited_delete and max_delete is None:
            raise ConfigError("operation=mirror requires safety.max_delete or allow_unlimited_delete=true")
        if operation == "archive" and not dry_run and not has_time_filter and not safety.get("allow_all_source_move", False):
            raise ConfigError("operation=archive deletes source files; configure a time filter or allow_all_source_move=true")
        if operation == "prune" and not dry_run and not (has_time_filter or has_filter):
            raise ConfigError("operation=prune deletes source files; configure age/date/include/exclude or use dry-run")
        if filters.get("filter_from") and any(filters.get(k) for k in ("include", "exclude", "exclude_extensions")):
            raise ConfigError("Do not combine filter_from with include/exclude/exclude_extensions; put all rules in filter_from")

    def resolve_age_flags(self, global_config: Dict[str, Any], cfg: Dict[str, Any]) -> Dict[str, str]:
        timezone = str(global_config.get("timezone") or self.env.get("TZ", "UTC"))
        now = now_local(timezone)
        age = cfg.get("age", {}) or {}
        date_filter = cfg.get("date", {}) or {}

        min_seconds: List[int] = []
        max_seconds: List[int] = []
        passthrough_min: Optional[str] = None
        passthrough_max: Optional[str] = None

        older = str(age.get("older_than", "") or "").strip()
        newer = str(age.get("newer_than", "") or "").strip()
        between = age.get("between", {}) or {}
        if isinstance(between, dict):
            older = older or str(between.get("older_than", "") or "").strip()
            newer = newer or str(between.get("newer_than", "") or "").strip()

        if older:
            seconds = parse_duration_to_seconds(older)
            if seconds is None:
                passthrough_min = older
            else:
                min_seconds.append(seconds)
        if newer:
            seconds = parse_duration_to_seconds(newer)
            if seconds is None:
                passthrough_max = newer
            else:
                max_seconds.append(seconds)

        before = str(date_filter.get("before", "") or "").strip()
        after = str(date_filter.get("after", "") or "").strip()
        between_date = date_filter.get("between", {}) or {}
        if isinstance(between_date, dict):
            after = after or str(between_date.get("after", "") or "").strip()
            before = before or str(between_date.get("before", "") or "").strip()

        before_dt = parse_datetime(before, timezone) if before else None
        after_dt = parse_datetime(after, timezone) if after else None
        if before_dt and after_dt and after_dt > before_dt:
            raise ConfigError(f"date.after {after} is later than date.before {before}; selected window is empty")
        if before_dt:
            delta = int((now - before_dt).total_seconds())
            if delta < 0:
                raise ConfigError(f"date.before {before} is in the future; selected window would include all files")
            min_seconds.append(delta)
        if after_dt:
            delta = int((now - after_dt).total_seconds())
            if delta < 0:
                raise ConfigError(f"date.after {after} is in the future; selected window is empty")
            max_seconds.append(delta)

        flags: Dict[str, str] = {}
        if min_seconds:
            flags["min_age"] = f"{max(min_seconds)}s"
        elif passthrough_min:
            flags["min_age"] = passthrough_min
        if max_seconds:
            flags["max_age"] = f"{min(max_seconds)}s"
        elif passthrough_max:
            flags["max_age"] = passthrough_max

        if min_seconds and max_seconds and max(min_seconds) > min(max_seconds):
            raise ConfigError("age/date filters produce an empty window: min-age is greater than max-age")
        return flags

    def preflight_source_delete(self, global_config: Dict[str, Any], cfg: Dict[str, Any], task: Dict[str, Any], dry_run: bool) -> Optional[Dict[str, Any]]:
        if dry_run:
            return None
        safety = cfg.get("safety", {}) or {}
        if safety.get("allow_unlimited_delete", False):
            log("Preflight source delete limits disabled by allow_unlimited_delete=true")
            return None
        max_delete = safety.get("max_delete")
        max_delete_size = safety.get("max_delete_size")
        max_delete = normalize_delete_limit(max_delete, "max_delete", bool(safety.get("allow_unlimited_delete", False)))
        max_delete_size = normalize_delete_size(max_delete_size, "max_delete_size", bool(safety.get("allow_unlimited_delete", False)))
        if max_delete is None and not max_delete_size:
            return None

        argv = [self.rclone_bin, "lsjson", task["source_path"], "--recursive", "--files-only"]
        argv.extend(self.common_flags(global_config, include_stats=False))
        argv.extend(self.filter_flags(cfg))
        argv.extend(self.age_flags(global_config, cfg))
        log(f"Preflight source delete count directory={task['directory']}")
        result = subprocess.run(argv, text=True, stdout=subprocess.PIPE)
        if result.returncode != 0:
            raise RuntimeError(f"preflight lsjson failed with code {result.returncode}")
        try:
            files = json.loads(result.stdout or "[]")
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"preflight lsjson returned invalid JSON: {exc}") from exc
        count = len(files)
        total_size = sum(int(item.get("Size") or 0) for item in files if not item.get("IsDir"))
        log(f"Preflight selected source files count={count} size={total_size}B")
        if max_delete is not None and count > int(max_delete):
            raise ConfigError(f"selected source files count {count} exceeds max_delete={max_delete}")
        if max_delete_size:
            limit = parse_size_to_bytes(str(max_delete_size))
            if limit is not None and total_size > limit:
                raise ConfigError(f"selected source files size {total_size}B exceeds max_delete_size={max_delete_size}")
        return {"selected_files": count, "selected_size_bytes": total_size}

    def build_rclone_command(
        self,
        global_config: Dict[str, Any],
        cfg: Dict[str, Any],
        task: Dict[str, Any],
        task_dir: Path,
        dry_run: bool,
    ) -> List[str]:
        operation = normalize_mode(cfg.get("operation", "copy"))
        if operation == "copy":
            argv = [self.rclone_bin, "copy", task["source_path"], task["target_path"]]
        elif operation == "mirror":
            argv = [self.rclone_bin, "sync", task["source_path"], task["target_path"]]
        elif operation == "archive":
            argv = [self.rclone_bin, "move", task["source_path"], task["target_path"]]
        elif operation == "prune":
            argv = [self.rclone_bin, "delete", task["source_path"]]
        elif operation == "check":
            argv = [self.rclone_bin, "check", task["source_path"], task["target_path"]]
        else:
            raise ConfigError(f"unsupported operation: {operation}")

        argv.extend(self.common_flags(global_config))
        argv.extend(self.filter_flags(cfg))
        argv.extend(self.age_flags(global_config, cfg))
        argv.extend(self.operation_flags(operation, cfg, task_dir))
        if dry_run:
            argv.append("--dry-run")
        return argv

    def common_flags(self, global_config: Dict[str, Any], include_stats: bool = True) -> List[str]:
        flags: List[str] = []
        rclone_config = str(global_config.get("rclone_config") or "").strip()
        if rclone_config:
            flags.extend(["--config", rclone_config])
        log_level = str(global_config.get("log_level") or "").strip()
        if log_level:
            flags.extend(["--log-level", log_level])
        if include_stats and global_config.get("stats"):
            flags.extend(["--stats", str(global_config["stats"])])
        for key, flag in (
            ("transfers", "--transfers"),
            ("checkers", "--checkers"),
            ("retries", "--retries"),
            ("low_level_retries", "--low-level-retries"),
        ):
            value = global_config.get(key)
            if value not in (None, ""):
                flags.extend([flag, str(value)])
        if global_config.get("checksum"):
            flags.append("--checksum")
        if global_config.get("size_only"):
            flags.append("--size-only")
        if global_config.get("metadata"):
            flags.append("--metadata")
        for flag_name in ("bwlimit", "tpslimit", "drive_chunk_size", "s3_chunk_size"):
            value = global_config.get(flag_name)
            if value:
                flags.extend(["--" + flag_name.replace("_", "-"), str(value)])
        return flags

    def filter_flags(self, cfg: Dict[str, Any]) -> List[str]:
        filters = cfg.get("filters", {}) or {}
        flags: List[str] = []
        for ext in normalize_extensions(as_list(filters.get("exclude_extensions"))):
            flags.extend(["--exclude", f"*.{ext}", "--exclude", f"**/*.{ext}"])
        for pattern in as_list(filters.get("include")):
            flags.extend(["--include", str(pattern)])
        for pattern in as_list(filters.get("exclude")):
            flags.extend(["--exclude", str(pattern)])
        for path in as_list(filters.get("exclude_from")):
            flags.extend(["--exclude-from", str(path)])
        for path in as_list(filters.get("filter_from")):
            flags.extend(["--filter-from", str(path)])
        for path in as_list(filters.get("files_from")):
            flags.extend(["--files-from", str(path)])
        for marker in as_list(filters.get("exclude_if_present")):
            flags.extend(["--exclude-if-present", str(marker)])
        return flags

    def age_flags(self, global_config: Dict[str, Any], cfg: Dict[str, Any]) -> List[str]:
        resolved = self.resolve_age_flags(global_config, cfg)
        flags: List[str] = []
        if resolved.get("min_age"):
            flags.extend(["--min-age", resolved["min_age"]])
        if resolved.get("max_age"):
            flags.extend(["--max-age", resolved["max_age"]])
        return flags

    def operation_flags(self, operation: str, cfg: Dict[str, Any], task_dir: Path) -> List[str]:
        flags: List[str] = []
        safety = cfg.get("safety", {}) or {}
        if operation in {"copy", "mirror", "archive"}:
            if self.supports_flag(command_for_mode(operation), "--combined"):
                flags.extend(["--combined", str(task_dir / "combined.txt")])
            if self.supports_flag(command_for_mode(operation), "--error"):
                flags.extend(["--error", str(task_dir / "errors.txt")])
        if operation == "mirror":
            max_delete = normalize_delete_limit(
                safety.get("max_delete"),
                "max_delete",
                bool(safety.get("allow_unlimited_delete", False)),
            )
            if max_delete is not None and not safety.get("allow_unlimited_delete", False):
                flags.extend(["--max-delete", str(max_delete)])
            max_delete_size = normalize_delete_size(
                safety.get("max_delete_size"),
                "max_delete_size",
                bool(safety.get("allow_unlimited_delete", False)),
            )
            if max_delete_size and self.supports_flag("sync", "--max-delete-size"):
                flags.extend(["--max-delete-size", str(max_delete_size)])
            if safety.get("delete_excluded") and safety.get("allow_delete_excluded"):
                flags.append("--delete-excluded")
        if operation in {"copy", "mirror", "archive"} and safety.get("backup_dir"):
            flags.extend(["--backup-dir", expand_runtime_template(str(safety["backup_dir"]), self.run_id)])
        if operation == "archive" and (cfg.get("archive", {}) or {}).get("delete_empty_source_dirs", False):
            flags.append("--delete-empty-src-dirs")
        if operation == "prune" and (cfg.get("prune", {}) or {}).get("rmdirs", True):
            flags.append("--rmdirs")
        return flags

    def supports_flag(self, command: str, flag: str) -> bool:
        key = (command, flag)
        if key in self.flag_cache:
            return self.flag_cache[key]
        try:
            result = subprocess.run([self.rclone_bin, command, "--help"], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            supported = result.returncode == 0 and flag in result.stdout
        except FileNotFoundError:
            supported = True
        self.flag_cache[key] = supported
        return supported


def log(message: str, level: str = "INFO") -> None:
    ts = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{ts}] {level}: {message}", flush=True)


def now_local(timezone: str) -> dt.datetime:
    if ZoneInfo is None:
        return dt.datetime.now(dt.timezone.utc)
    try:
        return dt.datetime.now(ZoneInfo(timezone))
    except Exception:
        return dt.datetime.now(dt.timezone.utc)


def env_bool(name: str, default: bool) -> bool:
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def env_int(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    try:
        return int(value)
    except ValueError as exc:
        raise ConfigError(f"{name} must be an integer") from exc


def split_list(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    text = str(value).replace("\n", ",")
    return [item.strip() for item in text.split(",") if item.strip()]


def as_list(value: Any) -> List[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return split_list(value)


def normalize_extensions(items: Iterable[Any]) -> List[str]:
    out = []
    for item in items:
        ext = str(item).strip()
        if not ext:
            continue
        if ext.startswith("*."):
            ext = ext[2:]
        elif ext.startswith("."):
            ext = ext[1:]
        if not ext or "/" in ext or "\\" in ext or ".." in ext or "*" in ext:
            raise ConfigError(f"invalid extension exclude: {item!r}")
        out.append(ext)
    return out


def normalize_mode(value: str) -> str:
    mode = str(value or "copy").strip().lower()
    aliases = {"sync": "mirror", "move": "archive", "delete": "prune"}
    mode = aliases.get(mode, mode)
    if mode not in VALID_MODES:
        raise ConfigError(f"unsupported mode {mode!r}; expected one of {', '.join(sorted(VALID_MODES))}")
    return mode


def command_for_mode(mode: str) -> str:
    return {"copy": "copy", "mirror": "sync", "archive": "move", "prune": "delete", "check": "check"}[mode]


def require_name(job: Dict[str, Any]) -> str:
    name = str(job.get("name") or "").strip()
    if not name:
        raise ConfigError("job.name is required")
    return name


def inferred_mode_from_env(env: Dict[str, str]) -> str:
    if str(env.get("RCLONE_SYNC_DELETE_SOURCE", "")).strip().lower() in {"1", "true", "yes", "y", "on"}:
        return "archive"
    if str(env.get("RCLONE_SYNC_DELETE_TARGET_EXTRAS", "")).strip().lower() in {"1", "true", "yes", "y", "on"}:
        return "mirror"
    return "copy"


def task_result_fields(
    job: Dict[str, Any],
    task: Dict[str, Any],
    operation: str,
    dry_run: bool,
    run_id: str,
    started: float,
    preflight: Optional[Dict[str, Any]],
    error: str = "",
) -> Dict[str, Any]:
    fields: Dict[str, Any] = {
        "job": require_name(job),
        "run_id": run_id,
        "directory": task["directory"],
        "mode": operation,
        "dry_run": dry_run,
        "duration": f"{time.monotonic() - started:.1f}s",
        "source": task["source_path"],
        "target": task["target_path"] or "<none>",
    }
    if preflight:
        fields["selected_files"] = preflight.get("selected_files")
        fields["selected_size_bytes"] = preflight.get("selected_size_bytes")
    if error:
        fields["error"] = error
    return fields


def format_slack_value(value: Any) -> str:
    text = (
        str(value)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("`", "'")
        .replace("\n", " ")
    )
    if len(text) > 700:
        return text[:697] + "..."
    return text


def normalize_delete_limit(value: Any, label: str, allow_unlimited: bool) -> Optional[int]:
    if allow_unlimited:
        return None
    if value in (None, ""):
        return None
    try:
        parsed = int(value)
    except (TypeError, ValueError) as exc:
        raise ConfigError(f"{label} must be a non-negative integer") from exc
    if parsed < 0:
        raise ConfigError(f"{label} must be non-negative unless allow_unlimited_delete=true")
    return parsed


def normalize_delete_size(value: Any, label: str, allow_unlimited: bool) -> str:
    if allow_unlimited:
        return ""
    if value in (None, ""):
        return ""
    text = str(value).strip()
    if parse_size_to_bytes(text) is None:
        raise ConfigError(f"{label} must be a size like 100G, 500M, or 1024")
    return text


def expand_runtime_template(value: str, run_id: str) -> str:
    run_date = run_id.split("_", 1)[0]
    return (
        value.replace("${RUN_ID}", run_id)
        .replace("${RUN_DATE}", run_date)
        .replace("{run_id}", run_id)
        .replace("{run_date}", run_date)
    )


def deep_merge(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for source in (base or {}, override or {}):
        for key, value in source.items():
            if isinstance(value, dict) and isinstance(result.get(key), dict):
                result[key] = deep_merge(result[key], value)
            else:
                result[key] = value
    return result


def get_nested_bool(data: Dict[str, Any], path: List[str], default: bool) -> bool:
    current: Any = data
    for key in path:
        if not isinstance(current, dict) or key not in current:
            return bool(default)
        current = current[key]
    if isinstance(current, bool):
        return current
    return str(current).strip().lower() in {"1", "true", "yes", "y", "on"}


def normalize_directory(directory: str) -> str:
    if directory == "":
        raise ConfigError("directory cannot be empty; use . for root")
    directory = directory.strip()
    if directory.startswith("/"):
        raise ConfigError(f"directory must be relative and cannot start with /: {directory!r}")
    directory = directory.strip("/")
    if directory in {"", "."}:
        return "."
    parts = Path(directory).parts
    if any(part in {"..", "."} for part in parts):
        raise ConfigError(f"directory must be relative and cannot contain . or ..: {directory!r}")
    return "/".join(parts)


def join_rclone_path(root: str, directory: str) -> str:
    root = str(root).strip()
    directory = normalize_directory(directory)
    if directory == ".":
        return root.rstrip("/") if root != "/" else root
    if root.endswith(":"):
        return f"{root}{directory}"
    return f"{root.rstrip('/')}/{directory}"


def validate_root(root: str, label: str, allow_root: bool) -> None:
    value = root.strip()
    if not value:
        raise ConfigError(f"{label} cannot be empty")
    if allow_root:
        return
    kind, _remote, path = parse_rclone_path(value)
    if value == "/" or (kind == "remote" and not path):
        raise ConfigError(f"{label}={value!r} is a root path; set allow_root_path=true if this is intentional")


def parse_rclone_path(path: str) -> Tuple[str, str, str]:
    if path.startswith("/") or path.startswith("./") or path.startswith("../"):
        return ("local", "", os.path.abspath(path))
    if path.startswith(":"):
        return ("connection", "", path)
    if ":" in path and "/" not in path.split(":", 1)[0]:
        remote, rest = path.split(":", 1)
        return ("remote", remote.lower(), rest.strip("/"))
    return ("local", "", os.path.abspath(path))


def validate_no_overlap(source: str, target: str) -> None:
    skind, sremote, spath = parse_rclone_path(source)
    tkind, tremote, tpath = parse_rclone_path(target)
    if skind != tkind or sremote != tremote:
        return
    if skind == "local":
        try:
            common = os.path.commonpath([spath, tpath])
        except ValueError:
            return
        if common == spath or common == tpath:
            raise ConfigError(f"source_root and target_root overlap: {source!r} -> {target!r}")
    elif skind == "remote":
        sp = spath.strip("/")
        tp = tpath.strip("/")
        if sp == tp or (sp and tp.startswith(sp + "/")) or (tp and sp.startswith(tp + "/")):
            raise ConfigError(f"source_root and target_root overlap on remote {sremote}: {source!r} -> {target!r}")


def remote_name(path: str) -> Optional[str]:
    path = str(path or "")
    if not path or path.startswith("/") or path.startswith(":"):
        return None
    if ":" not in path:
        return None
    left = path.split(":", 1)[0]
    if "/" in left:
        return None
    return left


def sanitize_env_name(name: str) -> str:
    return re.sub(r"[^A-Z0-9]", "_", name.upper())


def parse_datetime(value: str, timezone: str) -> dt.datetime:
    text = value.strip()
    if re.match(r"^\d{4}-\d{2}-\d{2}$", text):
        parsed = dt.datetime.fromisoformat(text + "T00:00:00")
    else:
        parsed = dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        if ZoneInfo is not None:
            try:
                parsed = parsed.replace(tzinfo=ZoneInfo(timezone))
            except Exception:
                parsed = parsed.replace(tzinfo=dt.timezone.utc)
        else:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed


def parse_duration_to_seconds(value: str) -> Optional[int]:
    text = str(value).strip()
    match = re.fullmatch(r"(\d+)(ms|s|m|h|d|w|M|y)", text)
    if not match:
        return None
    amount = int(match.group(1))
    unit = match.group(2)
    factors = {
        "ms": 0.001,
        "s": 1,
        "m": 60,
        "h": 3600,
        "d": 86400,
        "w": 604800,
        "M": 2592000,
        "y": 31536000,
    }
    return max(1, int(amount * factors[unit]))


def parse_size_to_bytes(value: str) -> Optional[int]:
    text = str(value).strip()
    match = re.fullmatch(r"(\d+)([KMGTP]?i?B?|B)?", text, re.IGNORECASE)
    if not match:
        return None
    amount = int(match.group(1))
    unit = (match.group(2) or "B").upper().replace("IB", "").replace("B", "")
    factors = {"": 1, "K": 1024, "M": 1024**2, "G": 1024**3, "T": 1024**4, "P": 1024**5}
    return amount * factors.get(unit, 1)


def safe_filename(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "_", value.strip())
    return cleaned.strip("._") or "root"


def shell_join_masked(argv: List[str]) -> str:
    return " ".join(shlex.quote(part) for part in argv)


def write_json(path: Path, data: Dict[str, Any]) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="rclone-sync runner")
    parser.add_argument("--config", default=os.environ.get("RCLONE_SYNC_CONFIG", "/config/jobs.yaml"))
    parser.add_argument("--job", default=os.environ.get("RCLONE_SYNC_JOB", ""))
    parser.add_argument("--notify-startup", action="store_true")
    parser.add_argument("--version", action="store_true")
    args = parser.parse_args()

    if args.version:
        print(VERSION)
        return 0

    try:
        if args.notify_startup:
            RcloneSync(args.config).notify_startup()
            return 0
        return RcloneSync(args.config).run(only_job=args.job or None)
    except ConfigError as exc:
        log(f"CONFIG ERROR: {exc}", level="ERROR")
        return 2
    except KeyboardInterrupt:
        log("Interrupted", level="ERROR")
        return 130


if __name__ == "__main__":
    sys.exit(main())
