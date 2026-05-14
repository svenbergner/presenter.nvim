# presenter.nvim
NeoVim plugin for showing a markdown file as slides.

## Presentation metadata

Add an optional metadata header at the start of a markdown file to show
presentation details in the footer:

```markdown
---
title: Parser Deep Dive
presenter: John Doe
date: 2026-05-11
figlet: true
figlet_font: slant
figlet_width: 100
figlet_kerning: true
---

# Intro

Welcome
```

`figlet` enables large slide headers when the `figlet` executable is available.
`figlet_font`, `figlet_width`, and `figlet_kerning` are optional.
