import { Editor, Extension } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import FontFamily from '@tiptap/extension-font-family'
import Image from '@tiptap/extension-image'
import Table from '@tiptap/extension-table'
import TableCell from '@tiptap/extension-table-cell'
import TableHeader from '@tiptap/extension-table-header'
import TableRow from '@tiptap/extension-table-row'
import TextStyle from '@tiptap/extension-text-style'
import { Plugin, PluginKey } from '@tiptap/pm/state'
import { Decoration, DecorationSet } from '@tiptap/pm/view'

// Tiptap has a first-party TextStyle extension but intentionally leaves the
// font-size attribute to applications. This small extension keeps that state
// in the document so it survives save/reopen and applies to Chinese text too.
const FontSize = Extension.create({
  name: 'fontSize',
  addGlobalAttributes() {
    return [{
      types: ['textStyle'],
      attributes: {
        fontSize: {
          default: null,
          parseHTML: element => element.style.fontSize || null,
          renderHTML: attributes => attributes.fontSize
            ? { style: `font-size: ${attributes.fontSize}` }
            : {},
        },
      },
    }]
  },
})

const $ = selector => document.querySelector(selector)
const bridge = payload => {
  if (window.webkit?.messageHandlers?.suixinji) {
    window.webkit.messageHandlers.suixinji.postMessage(payload)
  }
}

function imageCount() {
  return document.querySelectorAll('#editor img').length
}

const toolbarButtons = [...document.querySelectorAll('[data-action]')]
const searchBar = $('#search-bar')
const searchInput = $('#search-input')
const searchCount = $('#search-count')
const searchButtons = [...document.querySelectorAll('[data-search-action]')]
const modal = $('#image-modal')
const preview = $('#image-preview')
const heading = $('#heading')
const fontFamily = $('#font-family')
const fontSize = $('#font-size')
let suppressUpdate = false
let searchOpen = false

function textFromNode(node) {
  if (!node) return ''
  if (node.type === 'text') return node.text || ''
  return (node.content || []).map(textFromNode).join(node.type === 'paragraph' || node.type === 'heading' ? '\n' : '')
}

function deriveTitle(json) {
  const nodes = json?.content || []
  const text = nodes.map(textFromNode).join('\n')
  const title = text
    .split(/\r?\n/)
    .map(line => line.trim())
    .find(Boolean) || ''
  return title ? title.slice(0, 80) : '无标题'
}

function deriveOutline(json) {
  const items = []
  let index = 0

  const visit = node => {
    if (node?.type === 'heading') {
      const title = textFromNode(node).replace(/\s+/g, ' ').trim()
      if (title) {
        items.push({
          title: title.slice(0, 80),
          level: Math.max(1, Math.min(5, Number(node.attrs?.level) || 1)),
          index,
        })
        index += 1
      }
    }
    for (const child of node?.content || []) visit(child)
  }

  for (const node of json?.content || []) visit(node)
  return items
}

const searchPluginKey = new PluginKey('suixinjiSearch')

function findSearchMatches(doc, query) {
  const needle = query.trim().toLowerCase()
  if (!needle) return []

  const matches = []
  doc.descendants((node, pos) => {
    if (!node.isText || !node.text) return
    const text = node.text.toLowerCase()
    let offset = 0
    while (offset < text.length) {
      const start = text.indexOf(needle, offset)
      if (start < 0) break
      matches.push({ from: pos + start, to: pos + start + needle.length })
      offset = start + Math.max(needle.length, 1)
    }
  })
  return matches
}

function makeSearchState(doc, query, activeIndex = 0) {
  const normalizedQuery = query.trim()
  const matches = findSearchMatches(doc, normalizedQuery)
  const safeIndex = matches.length
    ? Math.min(Math.max(Number(activeIndex) || 0, 0), matches.length - 1)
    : 0
  return { query: normalizedQuery, activeIndex: safeIndex, matches }
}

const searchPlugin = new Plugin({
  key: searchPluginKey,
  state: {
    init: (_, instance) => makeSearchState(instance.doc, ''),
    apply(transaction, previous) {
      const meta = transaction.getMeta(searchPluginKey)
      if (meta) return makeSearchState(transaction.doc, meta.query || '', meta.activeIndex)
      if (transaction.docChanged && previous.query) {
        return makeSearchState(transaction.doc, previous.query, previous.activeIndex)
      }
      return previous
    },
  },
  props: {
    decorations(state) {
      const current = searchPluginKey.getState(state)
      if (!current?.matches.length) return DecorationSet.empty
      return DecorationSet.create(state.doc, current.matches.map((match, index) => {
        const active = index === current.activeIndex ? ' search-match-active' : ''
        return Decoration.inline(match.from, match.to, {
          class: `search-match${active}`,
        })
      }))
    },
  },
})

const SearchExtension = Extension.create({
  name: 'searchExtension',
  addProseMirrorPlugins() {
    return [searchPlugin]
  },
})

function activeOutlineIndex(currentEditor) {
  const { $from } = currentEditor.state.selection
  let activeHeadingPos = null

  for (let depth = $from.depth; depth >= 0; depth -= 1) {
    const node = $from.node(depth)
    if (node.type.name === 'heading' && node.textContent.trim()) {
      activeHeadingPos = $from.before(depth)
      break
    }
  }

  if (activeHeadingPos === null) return null

  let index = 0
  let activeIndex = null
  currentEditor.state.doc.descendants((node, pos) => {
    if (node.type.name !== 'heading' || !node.textContent.trim()) return
    if (pos === activeHeadingPos) activeIndex = index
    index += 1
  })
  return activeIndex
}

function sendOutlineSelection(currentEditor = editor) {
  bridge({ type: 'outlineSelection', index: activeOutlineIndex(currentEditor) })
}

function stripPastedBackground(html) {
  return html
    .replace(/\sstyle=(['"])(.*?)\1/gi, (_, quote, style) => {
      const cleaned = style
        .replace(/(?:^|;)\s*background(?:-color)?\s*:[^;]*/gi, '')
        .replace(/(?:^|;)\s*color\s*:[^;]*/gi, '')
        .trim()
      return cleaned ? ` style=${quote}${cleaned}${quote}` : ''
    })
    .replace(/\s(?:bgcolor|background)=(['"])[^'"]*\1/gi, '')
}

const editor = new Editor({
  element: $('#editor'),
  extensions: [
    StarterKit.configure({
      heading: { levels: [1, 2, 3, 4, 5] },
    }),
    TextStyle,
    FontSize,
    FontFamily.configure({ types: ['textStyle'] }),
    Image.configure({ inline: false, allowBase64: true }),
    Table.configure({ resizable: false }),
    TableRow,
    TableHeader,
    TableCell,
    SearchExtension,
  ],
  editorProps: {
    transformPastedHTML: stripPastedBackground,
    handlePaste(view, event) {
      const items = [...(event.clipboardData?.items || [])]
      const files = [...(event.clipboardData?.files || [])]
      const image = items.find(item => item.kind === 'file' && item.type.startsWith('image/'))
      const file = image?.getAsFile() || files.find(item => item.type.startsWith('image/'))
      if (!file) return false
      event.preventDefault()
      const reader = new FileReader()
      reader.onload = () => {
        if (typeof reader.result === 'string') {
          editor.chain().focus().setImage({ src: reader.result, alt: '粘贴的图片' }).run()
        }
      }
      reader.readAsDataURL(file)
      return true
    },
    handleKeyDown(view, event) {
      // A second Enter on an empty code line exits the code block. This keeps
      // normal text immediately appendable after a code snippet.
      if (event.key === 'Enter' && !event.shiftKey && editor.isActive('codeBlock')) {
        const { $from } = editor.state.selection
        if ($from.parent.type.name === 'codeBlock' && $from.parent.textContent.length === 0) {
          event.preventDefault()
          return editor.commands.exitCode()
        }
      }
      return false
    },
  },
  onCreate() {
    updateToolbar()
    bridge({ type: 'outline', items: deriveOutline(editor.getJSON()) })
    sendOutlineSelection()
    bridge({ type: 'ready', imageCount: imageCount() })
  },
  onUpdate({ editor: current }) {
    updateToolbar()
    if (searchOpen) {
      updateSearchUI()
      if (currentSearchState().matches.length) scrollToActiveSearchMatch()
    }
    if (suppressUpdate) return
    const json = current.getJSON()
    bridge({ type: 'outline', items: deriveOutline(json) })
    bridge({
      type: 'change',
      document: { version: 1, content: json },
      html: current.getHTML(),
      title: deriveTitle(json),
    })
    sendOutlineSelection(current)
  },
  onSelectionUpdate() {
    updateToolbar()
    sendOutlineSelection()
  },
})

function isTableAction(action) {
  return ['add-row', 'delete-row', 'add-column', 'delete-column', 'delete-table'].includes(action)
}

function runAction(action) {
  const chain = editor.chain().focus()
  switch (action) {
    case 'undo': chain.undo().run(); break
    case 'redo': chain.redo().run(); break
    case 'bold': chain.toggleBold().run(); break
    case 'italic': chain.toggleItalic().run(); break
    case 'strike': chain.toggleStrike().run(); break
    case 'bullet': chain.toggleBulletList().run(); break
    case 'ordered': chain.toggleOrderedList().run(); break
    case 'quote': chain.toggleBlockquote().run(); break
    case 'code': chain.toggleCodeBlock().run(); break
    case 'insert-table': chain.insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run(); break
    case 'add-row': chain.addRowAfter().run(); break
    case 'delete-row': chain.deleteRow().run(); break
    case 'add-column': chain.addColumnAfter().run(); break
    case 'delete-column': chain.deleteColumn().run(); break
    case 'delete-table': chain.deleteTable().run(); break
    default: return
  }
}

toolbarButtons.forEach(button => button.addEventListener('mousedown', event => event.preventDefault()))
toolbarButtons.forEach(button => button.addEventListener('click', () => runAction(button.dataset.action)))

heading.addEventListener('change', () => {
  const value = heading.value
  const chain = editor.chain().focus()
  if (value === 'paragraph') chain.setParagraph().run()
  else chain.setHeading({ level: Number(value) }).run()
})

fontFamily.addEventListener('change', () => {
  const chain = editor.chain().focus()
  if (fontFamily.value === 'system') chain.unsetFontFamily().run()
  else chain.setFontFamily(fontFamily.value).run()
})

fontSize.addEventListener('change', () => {
  editor.chain().focus().setMark('textStyle', { fontSize: fontSize.value }).run()
})

function updateToolbar() {
  document.querySelector('.ProseMirror')?.classList.toggle('is-empty', editor.isEmpty)
  const marks = { bold: 'bold', italic: 'italic', strike: 'strike', bullet: 'bulletList', ordered: 'orderedList', quote: 'blockquote', code: 'codeBlock' }
  toolbarButtons.forEach(button => {
    const action = button.dataset.action
    if (marks[action]) button.classList.toggle('is-active', editor.isActive(marks[action]))
    if (isTableAction(action)) button.disabled = !editor.isActive('table')
    if (action === 'undo') button.disabled = !editor.can().undo()
    if (action === 'redo') button.disabled = !editor.can().redo()
  })

  let headingValue = 'paragraph'
  for (let level = 1; level <= 5; level += 1) {
    if (editor.isActive('heading', { level })) headingValue = String(level)
  }
  heading.value = headingValue
  const attrs = editor.getAttributes('textStyle')
  fontFamily.value = attrs.fontFamily || 'system'
  fontSize.value = attrs.fontSize || '15px'
}

function currentSearchState() {
  return searchPluginKey.getState(editor.state) || makeSearchState(editor.state.doc, '')
}

function scrollToActiveSearchMatch() {
  requestAnimationFrame(() => {
    document.querySelector('#editor .search-match-active')?.scrollIntoView({
      block: 'nearest',
      inline: 'nearest',
    })
  })
}

function updateSearchUI() {
  const current = currentSearchState()
  const count = current.matches.length
  searchCount.textContent = count ? `${current.activeIndex + 1}/${count}` : '0/0'
  searchButtons.forEach(button => {
    if (button.dataset.searchAction === 'prev' || button.dataset.searchAction === 'next') {
      button.disabled = count === 0
    }
  })
}

function applySearchState(query, activeIndex = 0) {
  editor.view.dispatch(editor.state.tr.setMeta(searchPluginKey, {
    query,
    activeIndex,
  }))
  updateSearchUI()
  if (currentSearchState().matches.length) scrollToActiveSearchMatch()
}

function moveSearch(delta) {
  const current = currentSearchState()
  if (!current.matches.length) return
  const nextIndex = (current.activeIndex + delta + current.matches.length)
    % current.matches.length
  applySearchState(current.query, nextIndex)
}

function openSearch() {
  searchOpen = true
  searchBar.hidden = false
  searchInput.value = currentSearchState().query
  updateSearchUI()
  requestAnimationFrame(() => {
    searchInput.focus()
    searchInput.select()
  })
}

function closeSearch() {
  searchOpen = false
  searchBar.hidden = true
  searchInput.value = ''
  applySearchState('', 0)
  editor.commands.focus()
  bridge({ type: 'searchClosed' })
  return true
}

searchInput.addEventListener('input', () => {
  applySearchState(searchInput.value, 0)
})
searchInput.addEventListener('keydown', event => {
  if (event.key === 'Enter') {
    event.preventDefault()
    moveSearch(event.shiftKey ? -1 : 1)
  } else if (event.key === 'Escape') {
    event.preventDefault()
    closeSearch()
  }
})
searchButtons.forEach(button => button.addEventListener('mousedown', event => event.preventDefault()))
searchButtons.forEach(button => button.addEventListener('click', () => {
  switch (button.dataset.searchAction) {
    case 'prev': moveSearch(-1); break
    case 'next': moveSearch(1); break
    case 'close': closeSearch(); break
    default: break
  }
}))

function showPreview(src) {
  // The preview is a native window so it is not clipped by, or stacked inside,
  // the editor panel. Keep the old DOM elements only as a no-op compatibility
  // path while the native controller owns the visible preview.
  bridge({ type: 'imagePreview', visible: true, src })
}

function closePreview() {
  modal.hidden = true
  preview.removeAttribute('src')
  bridge({ type: 'imagePreview', visible: false })
  return true
}

$('#editor').addEventListener('click', event => {
  const image = event.target.closest('img')
  if (!image) return

  const pos = editor.view.posAtDOM(image, 0)
  if (pos >= 0) {
    event.preventDefault()
    editor.chain().focus().setNodeSelection(pos).run()
  }
})

$('#editor').addEventListener('dblclick', event => {
  const image = event.target.closest('img')
  if (image?.src) showPreview(image.src)
})
$('.image-modal-backdrop').addEventListener('click', closePreview)
preview.addEventListener('click', closePreview)
window.addEventListener('keydown', event => {
  if (event.key !== 'Escape') return
  if (!modal.hidden) {
    event.preventDefault()
    event.stopPropagation()
    closePreview()
  } else if (searchOpen) {
    event.preventDefault()
    event.stopPropagation()
    closeSearch()
  }
})

window.SuixinjiEditor = {
  openSearch,
  loadDocument(payload) {
    suppressUpdate = true
    try {
      if (payload?.content) editor.commands.setContent(payload.content)
      else if (payload?.html) editor.commands.setContent(payload.html)
      else editor.commands.clearContent()
      editor.commands.blur()
      updateToolbar()
      requestAnimationFrame(() => {
        bridge({ type: 'outline', items: deriveOutline(editor.getJSON()) })
        sendOutlineSelection()
        updateSearchUI()
        if (searchOpen && currentSearchState().matches.length) {
          scrollToActiveSearchMatch()
        }
        bridge({ type: 'rendered', imageCount: imageCount() })
      })
    } finally {
      suppressUpdate = false
    }
  },
  focus() {
    editor.commands.focus()
  },
  insertImage(src) {
    const ok = editor.chain().focus().setImage({ src, alt: '粘贴的图片' }).run()
    bridge({ type: 'imageInserted', ok: Boolean(ok) })
    return ok
  },
  insertHTML(html) {
    return editor.chain().focus().insertContent(stripPastedBackground(html)).run()
  },
  insertText(text) {
    return editor.chain().focus().insertContent(text).run()
  },
  selectAll() {
    return editor.commands.selectAll()
  },
  copy() {
    return document.execCommand('copy')
  },
  deleteSelection() {
    return editor.chain().focus().deleteSelection().run()
  },
  undo() {
    return editor.chain().focus().undo().run()
  },
  redo() {
    return editor.chain().focus().redo().run()
  },
  jumpToOutline(index) {
    let current = 0
    let target = null

    editor.state.doc.descendants((node, pos) => {
      if (target !== null) return false
      if (node.type.name === 'heading') {
        if (node.textContent.trim()) {
          if (current === index) target = pos + 1
          current += 1
        }
      }
      return true
    })

    if (target !== null) {
      editor.chain().focus().setTextSelection(target).scrollIntoView().run()
    }
  },
  closeSearch,
  closePreview,
}

$('#editor').addEventListener('error', event => {
  if (event.target?.tagName === 'IMG') bridge({ type: 'imageError' })
}, true)
