import SwiftUI
import WebKit

struct GraphView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    let projectId: UUID
    @Binding var isMinimized: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "chart.dots.scatter")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                Text("Knowledge Graph")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: { withAnimation { isMinimized.toggle() } }) {
                    Image(systemName: isMinimized ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help(isMinimized ? "Expand" : "Minimize")

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if !isMinimized {
                GraphWebView(
                    graphData: buildGraphData(),
                    onFileSelected: { filePath in
                        appState.openFile(projectId: projectId, filePath: filePath)
                    }
                )
                .frame(minHeight: 350)
            }
        }
        .background(isMinimized ? AnyShapeStyle(.bar) : AnyShapeStyle(Color(NSColor.windowBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: isMinimized ? 8 : 0))
        .shadow(color: .black.opacity(isMinimized ? 0.2 : 0), radius: isMinimized ? 8 : 0, y: isMinimized ? 2 : 0)
    }

    private func buildGraphData() -> GraphData {
        guard let project = appState.projects.first(where: { $0.id == projectId }),
              let files = project.files else {
            return GraphData(nodes: [], edges: [])
        }

        let flat = MarkdownFile.flatten(files)
        var nodes: [GraphNode] = []
        var edges: [GraphEdge] = []
        var nodeMap: [String: Int] = [:]

        for (i, file) in flat.enumerated() {
            let basename = (file.name as NSString).deletingPathExtension
            nodes.append(GraphNode(id: i, label: basename, path: file.path, relativePath: file.relativePath))
            nodeMap[file.relativePath.lowercased()] = i
            nodeMap[file.name.lowercased()] = i
            nodeMap[(file.name as NSString).deletingPathExtension.lowercased()] = i
        }

        guard WikiLinkResolver.regex != nil else {
            return GraphData(nodes: nodes, edges: edges)
        }

        for (sourceIdx, file) in flat.enumerated() {
            guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else { continue }
            let links = WikiLinkResolver.findLinks(in: content)

            for (_, inner) in links {
                let target = inner.split(separator: "|").first.map(String.init) ?? inner
                let targetCleaned = target.trimmingCharacters(in: .whitespaces).lowercased()
                let targetKey = targetCleaned.split(separator: "#").first.map(String.init) ?? targetCleaned

                if let targetIdx = nodeMap[targetKey], targetIdx != sourceIdx {
                    if !edges.contains(where: { $0.source == sourceIdx && $0.target == targetIdx }) {
                        edges.append(GraphEdge(source: sourceIdx, target: targetIdx))
                    }
                }
            }
        }

        return GraphData(nodes: nodes, edges: edges)
    }
}

// MARK: - Data Models

struct GraphNode {
    let id: Int
    let label: String
    let path: String
    let relativePath: String
}

struct GraphEdge: Equatable {
    let source: Int
    let target: Int
}

struct GraphData {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
}

// MARK: - Graph Web View

struct GraphWebView: NSViewRepresentable {
    let graphData: GraphData
    let onFileSelected: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "graphHandler")
        userController.add(context.coordinator, name: "exportHandler")

        let config = WKWebViewConfiguration()
        config.userContentController = userController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.onFileSelected = onFileSelected

        let html = generateGraphHTML()
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
    func makeCoordinator() -> GraphCoordinator { GraphCoordinator() }

    class GraphCoordinator: NSObject, WKScriptMessageHandler {
        var onFileSelected: ((String) -> Void)?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "graphHandler", let path = message.body as? String {
                DispatchQueue.main.async { self.onFileSelected?(path) }
            }
            if message.name == "exportHandler", let svgString = message.body as? String {
                DispatchQueue.main.async { self.saveSVG(svgString) }
            }
        }

        private func saveSVG(_ svg: String) {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.svg]
            panel.nameFieldStringValue = "knowledge-graph.svg"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? svg.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func escapeJS(_ s: String) -> String {
        JSEscaping.escapeForStringLiteral(s)
    }

    private func generateGraphHTML() -> String {
        let nodesJSON = graphData.nodes.map { n in
            "{\"id\":\(n.id),\"label\":\"\(escapeJS(n.label))\",\"path\":\"\(escapeJS(n.path))\"}"
        }.joined(separator: ",")

        let edgesJSON = graphData.edges.map { e in
            "{\"source\":\(e.source),\"target\":\(e.target)}"
        }.joined(separator: ",")

        return buildHTML(nodesJSON: nodesJSON, edgesJSON: edgesJSON)
    }

    private func buildHTML(nodesJSON: String, edgesJSON: String) -> String {
        """
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
:root{--bg:#0d1117;--fg:#e6edf3;--fg2:#8b949e;--edge:#30363d;--accent:#58a6ff;--node:#238636;--panel-bg:rgba(22,27,34,0.85);--border:#30363d;}
@media(prefers-color-scheme:light){:root{--bg:#fff;--fg:#1a1a2e;--fg2:#555;--edge:#d0d7de;--accent:#0969da;--node:#1a7f37;--panel-bg:rgba(255,255,255,0.9);--border:#e5e7eb;}}
*{margin:0;padding:0;box-sizing:border-box;user-select:none;}
html,body{width:100%;height:100%;overflow:hidden;background:var(--bg);font-family:-apple-system,BlinkMacSystemFont,sans-serif;}
svg{width:100%;height:100%;cursor:grab;}svg:active{cursor:grabbing;}
.edge{stroke:var(--edge);stroke-width:1.5;stroke-opacity:0.5;}
.node{cursor:pointer;}.node circle{stroke:var(--bg);stroke-width:2;transition:r 0.15s,fill 0.15s;}
.node circle:hover{filter:brightness(1.3);}
.node text{fill:var(--fg);font-size:11px;pointer-events:none;text-anchor:middle;}
.node.highlight circle{fill:var(--accent)!important;}

/* Control panels */
.panel{position:fixed;background:var(--panel-bg);backdrop-filter:blur(12px);border:1px solid var(--border);border-radius:10px;padding:14px 16px;color:var(--fg);font-size:11px;}
.panel-bl{bottom:16px;left:16px;}
.panel-br{bottom:16px;right:16px;width:240px;}
.panel h3{font-size:10px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:var(--fg2);margin-bottom:10px;display:flex;align-items:center;gap:6px;}
.panel h3 svg{width:14px;height:14px;fill:var(--fg2);}
.big-num{font-size:32px;font-weight:700;line-height:1;margin:4px 0 2px;}
.label{font-size:10px;color:var(--fg2);text-transform:uppercase;letter-spacing:0.5px;}
</style>
</head>
<body><svg id="graph"></svg>
"""
    + """

<!-- Node count panel -->
<div class="panel panel-bl">
  <div class="label">TOTAL CONNECTED NODES</div>
  <div class="big-num" id="node-count">0</div>
  <div class="label">FILES</div>
</div>

<!-- Controls panel -->
<div class="panel panel-br">
  <h3><svg viewBox="0 0 24 24"><path d="M3 17v2h6v-2H3zM3 5v2h10V5H3zm10 16v-2h8v-2h-8v-2h-2v6h2zM7 9v2H3v2h4v2h2V9H7zm14 4v-2H11v2h10zm-6-4h2V7h4V5h-4V3h-2v6z"/></svg>DISPLAY ENGINE</h3>
  <div style="margin-bottom:10px;">
    <div style="display:flex;justify-content:space-between;margin-bottom:4px;"><span>GRAVITY</span><span id="grav-val">0.014</span></div>
    <input type="range" id="gravity" min="0" max="0.05" step="0.001" value="0.014" style="width:100%;">
  </div>
  <div style="margin-bottom:10px;">
    <div style="display:flex;justify-content:space-between;margin-bottom:4px;"><span>LINK DISTANCE</span><span id="link-val">150px</span></div>
    <input type="range" id="linkDist" min="50" max="400" step="10" value="150" style="width:100%;">
  </div>
  <div style="margin-bottom:10px;">
    <div style="display:flex;justify-content:space-between;margin-bottom:4px;"><span>REPULSION</span><span id="rep-val">3.8k</span></div>
    <input type="range" id="repulsion" min="500" max="10000" step="100" value="3800" style="width:100%;">
  </div>
"""
    + """
  <div style="margin-bottom:12px;">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;">
      <span>ZOOM</span>
      <div style="display:flex;align-items:center;gap:8px;">
        <button onclick="zoomBtn(1.2)" style="background:none;border:1px solid var(--border);border-radius:4px;color:var(--fg);width:24px;height:24px;cursor:pointer;font-size:13px;">-</button>
        <span id="zoom-val" style="min-width:40px;text-align:center;">100%</span>
        <button onclick="zoomBtn(0.8)" style="background:none;border:1px solid var(--border);border-radius:4px;color:var(--fg);width:24px;height:24px;cursor:pointer;font-size:13px;">+</button>
      </div>
    </div>
  </div>
  <div style="display:flex;gap:8px;">
    <button onclick="resetView()" style="flex:1;padding:6px;background:var(--border);border:none;border-radius:6px;color:var(--fg);cursor:pointer;font-size:11px;font-weight:600;">Reset View</button>
    <button onclick="exportSVG()" style="flex:1;padding:6px;background:var(--accent);border:none;border-radius:6px;color:#fff;cursor:pointer;font-size:11px;font-weight:600;">Export SVG</button>
  </div>
</div>

<script>
const nodes = [\(nodesJSON)];
const edges = [\(edgesJSON)];
"""
    + buildGraphScript()
    + "</script></body></html>"
    }

    private func buildGraphScript() -> String {
        """
const W = window.innerWidth, H = window.innerHeight;
const svg = document.getElementById('graph');
let params = { gravity: 0.014, linkDist: 150, repulsion: 3800 };
let viewBox = { x: 0, y: 0, w: W, h: H };
const initVB = { x: 0, y: 0, w: W, h: H };

// Init positions
nodes.forEach((n, i) => {
  n.x = W/2 + (Math.random()-0.5)*Math.min(W,500);
  n.y = H/2 + (Math.random()-0.5)*Math.min(H,400);
  n.vx = 0; n.vy = 0; n.degree = 0;
});
edges.forEach(e => { nodes[e.source].degree++; nodes[e.target].degree++; });

// Count connected nodes
const connected = new Set();
edges.forEach(e => { connected.add(e.source); connected.add(e.target); });
document.getElementById('node-count').textContent = nodes.length;

function simulate() {
  for (let iter = 0; iter < 200; iter++) {
    // Repulsion
    for (let i = 0; i < nodes.length; i++) {
      for (let j = i+1; j < nodes.length; j++) {
        let dx = nodes[j].x - nodes[i].x, dy = nodes[j].y - nodes[i].y;
        let dist = Math.sqrt(dx*dx + dy*dy) || 1;
        let force = params.repulsion / (dist * dist);
        let fx = (dx/dist)*force, fy = (dy/dist)*force;
        nodes[i].vx -= fx; nodes[i].vy -= fy;
        nodes[j].vx += fx; nodes[j].vy += fy;
      }
    }
    // Springs
    edges.forEach(e => {
      let s = nodes[e.source], t = nodes[e.target];
      let dx = t.x - s.x, dy = t.y - s.y;
      let dist = Math.sqrt(dx*dx + dy*dy) || 1;
      let force = (dist - params.linkDist) * 0.01;
      let fx = (dx/dist)*force, fy = (dy/dist)*force;
      s.vx += fx; s.vy += fy; t.vx -= fx; t.vy -= fy;
    });
    // Gravity + damping
    nodes.forEach(n => {
      n.vx += (W/2 - n.x) * params.gravity;
      n.vy += (H/2 - n.y) * params.gravity;
      n.vx *= 0.85; n.vy *= 0.85;
      n.x += n.vx; n.y += n.vy;
    });
  }
}
simulate();

function updateViewBox() {
  svg.setAttribute('viewBox', viewBox.x+' '+viewBox.y+' '+viewBox.w+' '+viewBox.h);
  const zoom = Math.round(initVB.w / viewBox.w * 100);
  document.getElementById('zoom-val').textContent = zoom + '%';
}
updateViewBox();

function render() {
  // Clear
  while (svg.firstChild) svg.removeChild(svg.firstChild);
  // Edges
  edges.forEach(e => {
    const line = document.createElementNS('http://www.w3.org/2000/svg','line');
    line.classList.add('edge');
    line.setAttribute('x1', nodes[e.source].x); line.setAttribute('y1', nodes[e.source].y);
    line.setAttribute('x2', nodes[e.target].x); line.setAttribute('y2', nodes[e.target].y);
    svg.appendChild(line);
  });
"""
    + """
  // Nodes
  nodes.forEach(n => {
    const g = document.createElementNS('http://www.w3.org/2000/svg','g');
    g.classList.add('node');
    if (connected.has(n.id)) g.classList.add('highlight');
    const r = Math.max(5, Math.min(14, 4 + n.degree * 2.5));
    const circle = document.createElementNS('http://www.w3.org/2000/svg','circle');
    circle.setAttribute('cx', n.x); circle.setAttribute('cy', n.y); circle.setAttribute('r', r);
    circle.style.fill = connected.has(n.id) ? 'var(--accent)' : 'var(--fg2)';
    const text = document.createElementNS('http://www.w3.org/2000/svg','text');
    text.setAttribute('x', n.x); text.setAttribute('y', n.y - r - 5);
    text.textContent = n.label;
    g.appendChild(circle); g.appendChild(text);
    // Double-click to open
    g.addEventListener('dblclick', (ev) => {
      ev.stopPropagation();
      window.webkit.messageHandlers.graphHandler.postMessage(n.path);
    });
    // Drag node
    let dragging = false, ox, oy;
    g.addEventListener('mousedown', ev => { dragging = true; ox = ev.clientX; oy = ev.clientY; ev.stopPropagation(); });
    window.addEventListener('mousemove', ev => {
      if (!dragging) return;
      const scale = viewBox.w / svg.clientWidth;
      n.x += (ev.clientX - ox)*scale; n.y += (ev.clientY - oy)*scale;
      ox = ev.clientX; oy = ev.clientY;
      circle.setAttribute('cx', n.x); circle.setAttribute('cy', n.y);
      text.setAttribute('x', n.x); text.setAttribute('y', n.y - r - 5);
      // Update edges
      svg.querySelectorAll('.edge').forEach((line, i) => {
        const e = edges[i];
        if (e.source === n.id) { line.setAttribute('x1', n.x); line.setAttribute('y1', n.y); }
        if (e.target === n.id) { line.setAttribute('x2', n.x); line.setAttribute('y2', n.y); }
      });
    });
    window.addEventListener('mouseup', () => { dragging = false; });
    svg.appendChild(g);
  });
}
render();
"""
    + """

// Pan
const pan = {active:false,sx:0,sy:0,svx:0,svy:0};
svg.addEventListener('mousedown', ev => {
  pan.active = true; pan.sx = ev.clientX; pan.sy = ev.clientY;
  pan.svx = viewBox.x; pan.svy = viewBox.y;
});
svg.addEventListener('mousemove', ev => {
  if (!pan.active) return;
  const s = viewBox.w / svg.clientWidth;
  viewBox.x = pan.svx - (ev.clientX - pan.sx)*s;
  viewBox.y = pan.svy - (ev.clientY - pan.sy)*s;
  updateViewBox();
});
svg.addEventListener('mouseup', () => { pan.active = false; });

// Scroll/pinch zoom
svg.addEventListener('wheel', ev => {
  ev.preventDefault();
  const factor = ev.deltaY > 0 ? 1.08 : 0.92;
  const mx = viewBox.x + viewBox.w * (ev.offsetX / svg.clientWidth);
  const my = viewBox.y + viewBox.h * (ev.offsetY / svg.clientHeight);
  viewBox.w *= factor; viewBox.h *= factor;
  viewBox.x = mx - viewBox.w * (ev.offsetX / svg.clientWidth);
  viewBox.y = my - viewBox.h * (ev.offsetY / svg.clientHeight);
  updateViewBox();
}, {passive:false});

function zoomBtn(factor) {
  const cx = viewBox.x + viewBox.w/2, cy = viewBox.y + viewBox.h/2;
  viewBox.w *= factor; viewBox.h *= factor;
  viewBox.x = cx - viewBox.w/2; viewBox.y = cy - viewBox.h/2;
  updateViewBox();
}

function resetView() {
  viewBox.x = initVB.x; viewBox.y = initVB.y; viewBox.w = initVB.w; viewBox.h = initVB.h;
  updateViewBox();
  // Re-simulate with current params
  nodes.forEach(n => { n.x = W/2+(Math.random()-0.5)*300; n.y = H/2+(Math.random()-0.5)*300; n.vx=0; n.vy=0; });
  simulate(); render();
}
"""
    + """

function exportSVG() {
  // Clone SVG, resolve CSS vars to concrete colors
  const clone = svg.cloneNode(true);
  const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  const bg = isDark ? '#0d1117' : '#ffffff';
  const fg = isDark ? '#e6edf3' : '#1a1a2e';
  const edgeColor = isDark ? '#30363d' : '#d0d7de';
  const accent = isDark ? '#58a6ff' : '#0969da';
  clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
  clone.style.background = bg;
  clone.querySelectorAll('.edge').forEach(l => { l.style.stroke = edgeColor; });
  clone.querySelectorAll('.node circle').forEach(c => {
    if (c.style.fill.includes('accent')) c.style.fill = accent;
    else c.style.fill = isDark ? '#8b949e' : '#555';
    c.style.stroke = bg;
  });
  clone.querySelectorAll('.node text').forEach(t => { t.style.fill = fg; });
  const svgStr = '<?xml version="1.0"?>' + new XMLSerializer().serializeToString(clone);
  window.webkit.messageHandlers.exportHandler.postMessage(svgStr);
}

// Slider controls
document.getElementById('gravity').addEventListener('input', e => {
  params.gravity = parseFloat(e.target.value);
  document.getElementById('grav-val').textContent = params.gravity.toFixed(3);
  resimulate();
});
document.getElementById('linkDist').addEventListener('input', e => {
  params.linkDist = parseInt(e.target.value);
  document.getElementById('link-val').textContent = params.linkDist + 'px';
  resimulate();
});
document.getElementById('repulsion').addEventListener('input', e => {
  params.repulsion = parseInt(e.target.value);
  const v = params.repulsion >= 1000 ? (params.repulsion/1000).toFixed(1)+'k' : params.repulsion;
  document.getElementById('rep-val').textContent = v;
  resimulate();
});

let resimTimer;
function resimulate() {
  clearTimeout(resimTimer);
  resimTimer = setTimeout(() => { simulate(); render(); }, 50);
}
"""
    }
}
