---
name: writing-skill
description: Use when writing or editing Learn AI Agent repository documents, including AI Agent learning notes, paper summaries, technical reading notes, docs content, and reader-facing README updates. Follow the repository's Chinese, objective, structured, engineering-oriented writing style and keep README synchronized after docs changes.
---

# Writing Skill

Use this skill before creating or editing documentation in this repository.

## Workflow

1. Read the target source material or existing document before writing.
2. Read `references/style-guide.md` for the repository writing style.
3. Preserve the current document's structure unless the user asks for a rewrite.
4. Use Chinese by default, with technical terms kept in English when they are standard terms.
5. Keep images local to the document's topic directory and reference them with relative paths.
6. After creating or materially updating any file under `docs/`, update the root `README.md` so the new or changed document is reflected in the content map, learning path, and future-plan sections when relevant.
7. After editing, check headings, image paths, README synchronization, and whether the output accidentally uses banned labels such as `学习笔记`.

## Default document shape

For learning or technical reading documents, prefer:

1. Title
2. Source or reference link
3. Reading goal or core conclusion
4. Terminology table when the topic has repeated concepts
5. Background and problem statement
6. Structured sections with numbered headings
7. Tables for comparison, checklists, or concept mapping
8. Engineering implications and implementation checks
9. Key conclusions

## README synchronization

When a documentation task changes `docs/`, always inspect `README.md` before finishing.

Update only the parts affected by the document:

- Add or revise the document row in `当前内容`.
- Mark the matching `学习路径` stage as `已沉淀` and link the document, or add a new stage only when the topic does not fit the current route.
- Remove or adjust matching items in `后续计划` when the planned topic is now covered.
- Keep README reader-facing. Do not add maintenance details such as GitHub Pages workflow, build configuration, or writing-skill internals.

If the docs edit is a typo-only or formatting-only change, check README and leave it unchanged if the public content map remains accurate.

## Required reference

Read `references/style-guide.md` whenever the task asks to create, rewrite, polish, or extend a documentation file.
