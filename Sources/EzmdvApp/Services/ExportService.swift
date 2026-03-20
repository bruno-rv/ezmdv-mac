import AppKit

enum ExportService {
    static func exportHTML(markdown: String, fileName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = (fileName as NSString).deletingPathExtension + ".html"
        panel.message = "Export as standalone HTML"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let html = generateStandaloneHTML(markdown: markdown, title: (fileName as NSString).deletingPathExtension)

        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private static func generateStandaloneHTML(markdown: String, title: String) -> String {
        let escapedMD = markdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github-dark.min.css" media="(prefers-color-scheme: dark)">
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/styles/github.min.css" media="(prefers-color-scheme: light)">
        <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js"></script>
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.11/katex.min.css">
        <script src="https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.11/katex.min.js"></script>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/KaTeX/0.16.11/contrib/auto-render.min.js"></script>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/marked/15.0.7/marked.min.js"></script>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/mermaid/11.4.1/mermaid.min.js"></script>
        <style>
        :root { --bg:#fff;--fg:#1a1a2e;--border:#e5e7eb;--code-bg:#f6f8fa;--link:#0969da;--bq-border:#d0d7de;--fg2:#555; }
        @media(prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--border:#30363d;--code-bg:#161b22;--link:#58a6ff;--bq-border:#3b434b;--fg2:#8b949e;}}
        *{box-sizing:border-box}body{margin:0;padding:0;background:var(--bg);color:var(--fg);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;font-size:15px;line-height:1.7}
        .md{max-width:820px;margin:0 auto;padding:32px 40px 80px}
        .md h1,.md h2,.md h3{margin-top:1.5em;margin-bottom:.5em;font-weight:600}
        .md h1{font-size:2em;border-bottom:1px solid var(--border);padding-bottom:.3em}
        .md h2{font-size:1.5em;border-bottom:1px solid var(--border);padding-bottom:.3em}
        .md a{color:var(--link);text-decoration:none}.md a:hover{text-decoration:underline}
        .md img{max-width:100%;border-radius:6px}
        .md blockquote{margin:1em 0;padding:.5em 1em;border-left:4px solid var(--bq-border);color:var(--fg2);background:var(--code-bg);border-radius:0 6px 6px 0}
        .md pre{background:var(--code-bg);border-radius:8px;padding:16px;overflow-x:auto;font-size:13px;border:1px solid var(--border)}
        .md code{font-family:"SF Mono","Fira Code",Menlo,monospace;font-size:.88em}
        .md :not(pre)>code{background:var(--code-bg);padding:.2em .4em;border-radius:4px;border:1px solid var(--border)}
        .md table{border-collapse:collapse;width:100%;margin:1em 0}.md th,.md td{border:1px solid var(--border);padding:8px 12px;text-align:left}.md th{background:var(--code-bg);font-weight:600}
        .md hr{border:none;border-top:1px solid var(--border);margin:2em 0}
        .md ul,.md ol{padding-left:2em}.md li{margin:.3em 0}
        .mermaid{margin:1.5em 0;text-align:center}
        </style>
        </head>
        <body>
        <article class="md" id="content"></article>
        <script>
        marked.setOptions({gfm:true,breaks:false});
        mermaid.initialize({startOnLoad:false,theme:window.matchMedia('(prefers-color-scheme:dark)').matches?'dark':'default',securityLevel:'loose'});
        const md = `\(escapedMD)`;
        document.getElementById('content').innerHTML = marked.parse(md);
        hljs.highlightAll();
        document.querySelectorAll('.mermaid').forEach(async el => { try { await mermaid.run({nodes:[el]}); } catch(e){} });
        if(typeof renderMathInElement==='function') renderMathInElement(document.getElementById('content'),{delimiters:[{left:'$$',right:'$$',display:true},{left:'$',right:'$',display:false}],throwOnError:false});
        </script>
        </body></html>
        """
    }
}
