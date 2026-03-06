"""Tests for git-graph JS click handlers and context menu."""
import os

RESOURCES = os.path.join(os.path.dirname(__file__), "..", "Resources", "git-graph")

def read_file(name):
    with open(os.path.join(RESOURCES, name)) as f:
        return f.read()

def test_app_js_has_message_handler_calls():
    js = read_file("app.js")
    assert "window.webkit.messageHandlers.gitGraph.postMessage" in js

def test_app_js_has_context_menu():
    js = read_file("app.js")
    assert "context-menu" in js

def test_app_js_has_commit_click_handler():
    js = read_file("app.js")
    assert "commitSelected" in js

def test_app_js_has_copy_hash_action():
    js = read_file("app.js")
    assert "copyHash" in js

def test_app_js_has_open_in_browser_action():
    js = read_file("app.js")
    assert "openInBrowser" in js

def test_app_js_has_checkout_branch_action():
    js = read_file("app.js")
    assert "checkoutBranch" in js

def test_style_css_has_context_menu_styles():
    css = read_file("style.css")
    assert ".context-menu" in css

def test_commit_row_has_data_hash():
    js = read_file("app.js")
    assert "data-hash" in js
