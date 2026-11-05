"""Sphinx configuration of the documentation site (architecture.md §2.7)."""

project = "TimeTracking"
author = "Michael Goerz"
copyright = "2026, Michael Goerz"

extensions = ["myst_parser", "sphinx_design"]
exclude_patterns = [".venv", "_build", "README.md"]
source_suffix = {".md": "markdown"}
root_doc = "index"

# The specs write placeholders such as <task> as plain text, and no page needs
# raw HTML, so both stay literal.
myst_disable_syntax = ["html_block", "html_inline"]
myst_enable_extensions = ["attrs_block", "colon_fence"]
myst_heading_anchors = 3

# Straight quotes become curly; "--" in prose stays as written.
smartquotes_action = "q"

html_theme = "furo"
html_title = "TimeTracking"
html_static_path = ["_static"]
html_css_files = ["figures.css"]
html_logo = "_static/logo.svg"
html_favicon = "_static/logo.svg"
html_copy_source = False
html_show_sourcelink = False
html_theme_options = {
    "source_repository": "https://github.com/goerz/TimeTracking",
    "source_branch": "master",
    "source_directory": "docs/",
    "top_of_page_buttons": ["view"],
}
