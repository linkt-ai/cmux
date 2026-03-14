"""Tests for git-graph static web assets.

These tests verify the static files exist and contain required
entry points, CSS properties, and HTML structure. Run locally
(no VM needed) since they only check file contents.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GRAPH_DIR = ROOT / "Resources" / "git-graph"

# Module-level constants — read each file once
CSS_TEXT = (GRAPH_DIR / "style.css").read_text()
JS_TEXT = (GRAPH_DIR / "app.js").read_text()
HTML_TEXT = (GRAPH_DIR / "index.html").read_text()
PBXPROJ_TEXT = (ROOT / "GhosttyTabs.xcodeproj" / "project.pbxproj").read_text()


# --- Phase 1: CSS Theme System ---

def test_style_css_exists():
    assert (GRAPH_DIR / "style.css").is_file(), "style.css not found"


def test_style_css_has_dark_light_themes():
    # Custom properties are referenced in CSS rules (set by JS at runtime)
    assert "--graph-bg" in CSS_TEXT, "Missing --graph-bg custom property"
    assert "--commit-hash-color" in CSS_TEXT, "Missing --commit-hash-color"
    assert "--message-color" in CSS_TEXT, "Missing --message-color"
    assert "--secondary-color" in CSS_TEXT, "Missing --secondary-color"


def test_style_css_has_commit_styling():
    assert "monospace" in CSS_TEXT, "Commit hash should use monospace font"


def test_style_css_scrollable_container():
    assert "overflow" in CSS_TEXT, "Container should be scrollable"


# --- Phase 2: HTML Shell + JS Graph Engine ---

def test_index_html_exists():
    assert (GRAPH_DIR / "index.html").is_file(), "index.html not found"


def test_index_html_structure():
    assert "graph-container" in HTML_TEXT, "Missing graph-container div"
    assert "app.js" in HTML_TEXT, "Must load app.js"
    assert "style.css" in HTML_TEXT, "Must load style.css"
    assert "viewport" in HTML_TEXT, "Must have meta viewport"
    assert "charset" in HTML_TEXT.lower(), "Must declare charset"


def test_app_js_exists():
    assert (GRAPH_DIR / "app.js").is_file(), "app.js not found"


def test_app_js_has_update_graph():
    assert "window.updateGraph" in JS_TEXT, "Missing window.updateGraph entry point"


def test_app_js_has_apply_theme():
    assert "window.applyTheme" in JS_TEXT, "Missing window.applyTheme entry point"


def test_app_js_has_lane_assignment():
    # Must handle lane/column assignment for branch visualization
    assert re.search(r"lane|column", JS_TEXT, re.IGNORECASE), "Missing lane/column assignment logic"


def test_app_js_has_svg_generation():
    assert "createElementNS" in JS_TEXT or "svg" in JS_TEXT.lower(), "Missing SVG generation"


def test_app_js_handles_merge_parents():
    assert "parents" in JS_TEXT, "Must handle parent references for merge commits"


# --- Phase 3: Xcode Build Phase ---

def test_build_phase_copies_git_graph():
    """Verify project.pbxproj contains rsync for git-graph directory."""
    assert "git-graph" in PBXPROJ_TEXT, "project.pbxproj must reference git-graph for build phase copy"


def test_build_phase_git_graph_rsync():
    """Verify the rsync command copies from Resources/git-graph."""
    assert "Resources/git-graph" in PBXPROJ_TEXT, "rsync source should be Resources/git-graph"
