"""Tests for git-graph JS click handlers and context menu."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GRAPH_DIR = ROOT / "Resources" / "git-graph"

JS_TEXT = (GRAPH_DIR / "app.js").read_text()
CSS_TEXT = (GRAPH_DIR / "style.css").read_text()

def test_app_js_has_message_handler_calls():
    assert "window.webkit.messageHandlers.gitGraph.postMessage" in JS_TEXT

def test_app_js_has_context_menu():
    assert "context-menu" in JS_TEXT

def test_app_js_has_copy_hash_action():
    assert "copyHash" in JS_TEXT

def test_app_js_has_open_in_browser_action():
    assert "openInBrowser" in JS_TEXT

def test_app_js_has_checkout_branch_action():
    assert "checkoutBranch" in JS_TEXT

def test_style_css_has_context_menu_styles():
    assert ".context-menu" in CSS_TEXT

def test_commit_row_has_data_hash():
    assert "data-hash" in JS_TEXT
