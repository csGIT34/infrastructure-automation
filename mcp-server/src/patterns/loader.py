"""Load pattern definitions from config/patterns/*.yaml"""

import logging
import os
from pathlib import Path
from typing import Any

import yaml

logger = logging.getLogger(__name__)

# Default: look for config relative to repo root
# In Docker the layout is /app/src/... so REPO_ROOT resolves to /
# Use PATTERNS_DIR env var to override (set in Dockerfile)
REPO_ROOT = Path(__file__).parent.parent.parent.parent
PATTERNS_DIR = Path(
    os.environ.get("PATTERNS_DIR", str(REPO_ROOT / "config" / "patterns"))
)

# Module-level cache
_patterns_cache: dict[str, dict[str, Any]] | None = None


def load_patterns(patterns_dir: Path | None = None) -> dict[str, dict[str, Any]]:
    """Load all pattern definitions from YAML files.

    Results are cached after first load. Pass patterns_dir to bypass cache.

    Returns:
        Dict mapping pattern name to full pattern definition.
    """
    global _patterns_cache

    if patterns_dir is None and _patterns_cache is not None:
        return _patterns_cache

    directory = patterns_dir or PATTERNS_DIR
    patterns: dict[str, dict[str, Any]] = {}

    if not directory.exists():
        logger.warning("Patterns directory not found: %s", directory)
        return patterns

    for pattern_file in directory.glob("*.yaml"):
        with open(pattern_file) as f:
            pattern = yaml.safe_load(f)
            if pattern and "name" in pattern:
                patterns[pattern["name"]] = pattern
                logger.debug("Loaded pattern: %s", pattern["name"])

    logger.info("Loaded %d patterns from %s", len(patterns), directory)

    if patterns_dir is None:
        _patterns_cache = patterns

    return patterns


def clear_cache() -> None:
    """Clear the patterns cache (useful for testing)."""
    global _patterns_cache
    _patterns_cache = None
