import { EditorView, keymap, lineNumbers, highlightActiveLine, highlightActiveLineGutter, drawSelection, dropCursor, highlightSpecialChars } from '@codemirror/view';
import { EditorState, Compartment } from '@codemirror/state';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import { languages } from '@codemirror/language-data';
import { defaultKeymap, indentWithTab, history, historyKeymap } from '@codemirror/commands';
import { syntaxHighlighting, defaultHighlightStyle, indentOnInput, bracketMatching, foldGutter, foldKeymap } from '@codemirror/language';
import { searchKeymap, highlightSelectionMatches } from '@codemirror/search';
import { autocompletion, completionKeymap, acceptCompletion } from '@codemirror/autocomplete';
import { oneDark } from '@codemirror/theme-one-dark';

// --- Slash commands ---
const slashCommands = [
  { label: '/h1', detail: 'Heading 1', insert: '# ' },
  { label: '/h2', detail: 'Heading 2', insert: '## ' },
  { label: '/h3', detail: 'Heading 3', insert: '### ' },
  { label: '/ul', detail: 'Bullet list', insert: '- ' },
  { label: '/ol', detail: 'Numbered list', insert: '1. ' },
  { label: '/task', detail: 'Task list', insert: '- [ ] ' },
  { label: '/code', detail: 'Code block', insert: '```\n\n```' },
  { label: '/quote', detail: 'Blockquote', insert: '> ' },
  { label: '/table', detail: 'Table', insert: '| Column 1 | Column 2 |\n|----------|----------|\n| Cell 1   | Cell 2   |' },
  { label: '/hr', detail: 'Divider', insert: '---\n' },
  { label: '/link', detail: 'Link', insert: '[text](url)' },
  { label: '/image', detail: 'Image', insert: '![alt](url)' },
  { label: '/bold', detail: 'Bold', insert: '**text**' },
  { label: '/italic', detail: 'Italic', insert: '*text*' },
];

function slashCompletion(context) {
  const before = context.matchBefore(/\/\w*/);
  if (!before || before.from === before.to && !context.explicit) return null;
  return {
    from: before.from,
    options: slashCommands.map(cmd => ({
      label: cmd.label,
      detail: cmd.detail,
      apply: cmd.insert,
    })),
  };
}

// --- Theme compartment for dark/light switching ---
const themeCompartment = new Compartment();

const lightTheme = EditorView.theme({
  '&': { height: '100%', fontSize: '14px' },
  '.cm-content': { fontFamily: 'Menlo, Monaco, "Courier New", monospace', padding: '16px 20px' },
  '.cm-gutters': { backgroundColor: '#f8f9fa', color: '#999', borderRight: '1px solid #e0e0e0' },
  '.cm-activeLineGutter': { backgroundColor: '#e8f0fe' },
  '.cm-activeLine': { backgroundColor: '#f0f4ff' },
  '.cm-scroller': { overflow: 'auto' },
});

const darkTheme = EditorView.theme({
  '&': { height: '100%', fontSize: '14px' },
  '.cm-content': { fontFamily: 'Menlo, Monaco, "Courier New", monospace', padding: '16px 20px' },
  '.cm-gutters': { backgroundColor: '#1a1e2e', color: '#555', borderRight: '1px solid #2a2e3e' },
  '.cm-activeLineGutter': { backgroundColor: '#1e2535' },
  '.cm-activeLine': { backgroundColor: '#1a2030' },
  '.cm-scroller': { overflow: 'auto' },
});

// --- Editor Manager ---
class MarkdownEditorManager {
  constructor() {
    this.editor = null;
    this.debounceTimer = null;
    this.debounceMs = 300;
    this.isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  }

  init(container, initialContent) {
    if (this.editor) {
      this.editor.destroy();
    }

    const extensions = [
      lineNumbers(),
      highlightActiveLineGutter(),
      highlightSpecialChars(),
      history(),
      foldGutter(),
      drawSelection(),
      dropCursor(),
      indentOnInput(),
      bracketMatching(),
      highlightActiveLine(),
      highlightSelectionMatches(),
      EditorView.lineWrapping,
      markdown({ base: markdownLanguage, codeLanguages: languages }),
      syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
      autocompletion({ override: [slashCompletion, wikiLinkCompletion] }),
      keymap.of([
        ...defaultKeymap,
        ...historyKeymap,
        ...searchKeymap,
        ...foldKeymap,
        ...completionKeymap,
        indentWithTab,
      ]),
      // Theme
      themeCompartment.of(this.isDark ? [oneDark, darkTheme] : [lightTheme]),

      // Listen for changes
      EditorView.updateListener.of((update) => {
        if (update.docChanged) {
          this.onDocChanged();
        }
      }),
    ];

    this.editor = new EditorView({
      state: EditorState.create({
        doc: initialContent || '',
        extensions,
      }),
      parent: container,
    });

    // Listen for theme changes
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
      this.isDark = e.matches;
      if (this.editor) {
        this.editor.dispatch({
          effects: themeCompartment.reconfigure(
            this.isDark ? [oneDark, darkTheme] : [lightTheme]
          ),
        });
      }
    });
  }

  onDocChanged() {
    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      const content = this.getContent();
      // Notify Swift
      if (window.webkit?.messageHandlers?.editorHandler) {
        window.webkit.messageHandlers.editorHandler.postMessage(content);
      }
      // Update live preview if visible
      const previewPane = document.getElementById('render-pane');
      if (previewPane && previewPane.offsetParent !== null) {
        renderToElement(content, previewPane);
      }
    }, this.debounceMs);
  }

  getContent() {
    return this.editor ? this.editor.state.doc.toString() : '';
  }

  setContent(content) {
    if (!this.editor) return;
    const currentContent = this.editor.state.doc.toString();
    if (content === currentContent) return;
    // Preserve cursor position
    const cursor = this.editor.state.selection.main.head;
    this.editor.dispatch({
      changes: { from: 0, to: this.editor.state.doc.length, insert: content },
    });
    const newLen = content.length;
    if (cursor <= newLen) {
      this.editor.dispatch({ selection: { anchor: cursor } });
    }
  }

  focus() {
    if (this.editor) {
      this.editor.focus();
    }
  }

  destroy() {
    if (this.editor) {
      this.editor.destroy();
      this.editor = null;
    }
  }
}

// --- Render helper (reuses the global marked/hljs/mermaid from markdown.html) ---
async function renderToElement(md, el) {
  if (typeof marked === 'undefined') return;
  el.innerHTML = marked.parse(md);

  // Mermaid
  const mermaidEls = el.querySelectorAll('.mermaid');
  if (mermaidEls.length > 0 && typeof mermaid !== 'undefined') {
    try { await mermaid.run({ nodes: mermaidEls }); }
    catch(e) { console.error('Mermaid error:', e); }
  }

  // KaTeX
  if (typeof renderMathInElement === 'function') {
    renderMathInElement(el, {
      delimiters: [
        { left: '$$', right: '$$', display: true },
        { left: '$', right: '$', display: false },
        { left: '\\[', right: '\\]', display: true },
        { left: '\\(', right: '\\)', display: false },
      ],
      throwOnError: false,
    });
  }

  // Highlight remaining code blocks
  if (typeof hljs !== 'undefined') {
    el.querySelectorAll('pre code:not(.hljs)').forEach(b => hljs.highlightElement(b));
  }
}

// --- Wiki-link autocomplete ---
let _projectFiles = []; // [{name, path, relativePath}]

function wikiLinkCompletion(context) {
  // Match [[<partial text>
  const before = context.matchBefore(/\[\[([^\]]*)/);
  if (!before) return null;
  const query = before.text.slice(2).toLowerCase(); // strip the [[
  const from = before.from + 2; // position after [[

  const options = _projectFiles
    .filter(f => {
      const name = f.name.toLowerCase().replace(/\.md$/, '');
      const rel = f.relativePath.toLowerCase().replace(/\.md$/, '');
      return name.includes(query) || rel.includes(query);
    })
    .slice(0, 15)
    .map(f => ({
      label: f.name.replace(/\.md$/, ''),
      detail: f.relativePath,
      apply: f.name.replace(/\.md$/, '') + ']]',
    }));

  return { from, options };
}

// Called from HTML when Swift sends project files
window._updateEditorFiles = function(files) {
  _projectFiles = files;
};

// --- Export globally ---
window.EditorManager = MarkdownEditorManager;
window.renderToElement = renderToElement;
