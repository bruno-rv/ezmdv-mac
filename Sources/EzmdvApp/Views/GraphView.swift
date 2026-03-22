import SwiftUI
import WebKit

struct GraphView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    let projectId: UUID
    @Binding var isMinimized: Bool

    @State private var filterSearch: String = ""
    @State private var showOrphansOnly: Bool = false
    @State private var folderFilter: String = ""

    var body: some View {
        let graphData = buildGraphData()
        let folders = Array(Set(graphData.nodes.compactMap { $0.folder.isEmpty ? nil : $0.folder })).sorted()
        return VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.cyan)
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
                // Filter bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    TextField("Filter nodes…", text: $filterSearch)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !filterSearch.isEmpty {
                        Button(action: { filterSearch = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    Toggle("Orphans", isOn: $showOrphansOnly)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                        .help("Show only notes with no links")

                    if folders.count > 1 {
                        Divider().frame(height: 14)
                        Picker("", selection: $folderFilter) {
                            Text("All Folders").tag("")
                            ForEach(folders, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        .font(.system(size: 11))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.06))

                Divider()

                GraphWebView(
                    graphData: graphData,
                    filterSearch: filterSearch,
                    showOrphansOnly: showOrphansOnly,
                    folderFilter: folderFilter,
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

        let flat = MarkdownFile.flatten(files).filter { !$0.isDirectory }
        var nodes: [GraphNode] = []
        var edges: [GraphEdge] = []
        var nodeMap: [String: Int] = [:]

        for (i, file) in flat.enumerated() {
            let basename = (file.name as NSString).deletingPathExtension
            let parts = file.relativePath.split(separator: "/")
            let folder = parts.count > 1 ? String(parts[0]) : ""
            let content = appState.getContent(for: file.path) ?? ""
            let preview = String(content.prefix(3000))
            nodes.append(GraphNode(id: i, label: basename, path: file.path, relativePath: file.relativePath, folder: folder, preview: preview))
            nodeMap[file.relativePath.lowercased()] = i
            nodeMap[file.name.lowercased()] = i
            nodeMap[(file.name as NSString).deletingPathExtension.lowercased()] = i
        }

        for (sourceIdx, file) in flat.enumerated() {
            for targetName in appState.wikiLinkIndex.outgoingLinks(from: file.path) {
                if let targetIdx = nodeMap[targetName], targetIdx != sourceIdx {
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
    let folder: String
    let preview: String
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
    var filterSearch: String = ""
    var showOrphansOnly: Bool = false
    var folderFilter: String = ""
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

    func updateNSView(_ webView: WKWebView, context: Context) {
        let filterChanged = context.coordinator.lastFilterSearch != filterSearch
            || context.coordinator.lastOrphansOnly != showOrphansOnly
            || context.coordinator.lastFolderFilter != folderFilter
        guard filterChanged else { return }
        context.coordinator.lastFilterSearch = filterSearch
        context.coordinator.lastOrphansOnly = showOrphansOnly
        context.coordinator.lastFolderFilter = folderFilter
        let escaped = JSEscaping.escapeForStringLiteral(filterSearch)
        let escapedFolder = JSEscaping.escapeForStringLiteral(folderFilter)
        webView.evaluateJavaScript(
            "typeof applyGraphFilter !== 'undefined' && applyGraphFilter('\(escaped)', \(showOrphansOnly), '\(escapedFolder)')",
            completionHandler: nil
        )
    }

    func makeCoordinator() -> GraphCoordinator { GraphCoordinator() }

    class GraphCoordinator: NSObject, WKScriptMessageHandler {
        var onFileSelected: ((String) -> Void)?
        var lastFilterSearch: String = ""
        var lastOrphansOnly: Bool = false
        var lastFolderFilter: String = ""

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

    private func generateGraphHTML() -> String {
        let esc = JSEscaping.escapeForStringLiteral
        let nodesJSON = graphData.nodes.map { n in
            "{\"id\":\(n.id),\"label\":\"\(esc(n.label))\",\"path\":\"\(esc(n.path))\",\"folder\":\"\(esc(n.folder))\",\"preview\":\"\(esc(n.preview))\"}"
        }.joined(separator: ",")

        let edgesJSON = graphData.edges.map { e in
            "{\"source\":\(e.source),\"target\":\(e.target)}"
        }.joined(separator: ",")

        return """
<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
*{margin:0;padding:0;box-sizing:border-box;user-select:none;}
html,body{width:100%;height:100%;overflow:hidden;background:#05080f;font-family:-apple-system,BlinkMacSystemFont,sans-serif;}
canvas{width:100%;height:100%;position:absolute;top:0;left:0;}
#stars{z-index:0;}#graph{z-index:1;cursor:grab;}#graph:active{cursor:grabbing;}

/* Preview panel */
.preview-panel{position:fixed;z-index:200;width:384px;background:rgba(10,14,26,0.92);backdrop-filter:blur(16px);border:1px solid rgba(100,160,255,0.2);border-radius:12px;color:#e0e8f0;font-size:12px;display:none;box-shadow:0 8px 32px rgba(0,0,0,0.5),0 0 1px rgba(100,160,255,0.3);}
.preview-header{display:flex;align-items:center;padding:8px 12px;border-bottom:1px solid rgba(100,160,255,0.15);cursor:move;}
.preview-title{flex:1;font-weight:600;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.preview-btn{background:none;border:none;color:rgba(200,220,255,0.6);cursor:pointer;font-size:14px;width:24px;height:24px;display:flex;align-items:center;justify-content:center;border-radius:4px;}
.preview-btn:hover{background:rgba(100,160,255,0.15);color:#fff;}
.preview-body{padding:14px;font-size:12px;line-height:1.6;color:rgba(200,220,255,0.7);max-height:220px;overflow-y:auto;}
.preview-body.expanded{max-height:60vh;}
.preview-body h1,.preview-body h2,.preview-body h3{color:rgba(220,235,255,0.9);margin:8px 0 4px;font-size:13px;}
.preview-body h1{font-size:15px;border-bottom:1px solid rgba(100,160,255,0.15);padding-bottom:4px;}
.preview-body strong{color:rgba(220,235,255,0.85);}
.preview-body em{color:rgba(180,200,240,0.7);}
.preview-body a{color:#58a6ff;text-decoration:none;}
.preview-body code{background:rgba(100,160,255,0.1);padding:1px 5px;border-radius:3px;font-family:ui-monospace,monospace;font-size:10px;color:rgba(200,220,255,0.8);}
.preview-body pre{background:rgba(0,10,30,0.5);border:1px solid rgba(100,160,255,0.12);border-radius:6px;padding:8px 10px;margin:6px 0;overflow-x:auto;}
.preview-body pre code{background:none;padding:0;font-size:10px;color:rgba(160,200,255,0.75);}
.preview-body ol,.preview-body ul{padding-left:18px;margin:4px 0;}
.preview-body li{margin:2px 0;}
.preview-body blockquote{border-left:3px solid rgba(100,160,255,0.3);padding:4px 10px;margin:6px 0;color:rgba(180,200,240,0.7);font-style:italic;background:rgba(100,160,255,0.04);border-radius:0 4px 4px 0;}
.preview-body hr{border:none;border-top:1px solid rgba(100,160,255,0.15);margin:10px 0;}
.preview-body .collapse-hdr{cursor:pointer;display:flex;align-items:center;gap:4px;}
.preview-body .collapse-hdr::before{content:'\\25BE';font-size:9px;color:rgba(100,160,255,0.4);transition:transform 0.2s;}
.preview-body .collapse-hdr.collapsed::before{transform:rotate(-90deg);}
.preview-body .collapse-section{overflow:hidden;transition:max-height 0.25s ease;}
.preview-body .collapse-section.hidden{max-height:0!important;}
.preview-panel.expanded-panel{width:620px;}
.preview-panel.collapsed-panel .preview-body{display:none;}
.preview-panel.collapsed-panel{border-radius:8px;}

/* Controls */
.ctrl{position:fixed;bottom:16px;right:16px;background:rgba(10,14,26,0.85);backdrop-filter:blur(12px);border:1px solid rgba(100,160,255,0.15);border-radius:10px;padding:12px 14px;color:rgba(200,220,255,0.8);font-size:10px;width:220px;z-index:50;}
.ctrl h3{font-size:9px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;color:rgba(100,180,255,0.5);margin-bottom:8px;}
.ctrl-row{display:flex;justify-content:space-between;margin-bottom:3px;}.ctrl input[type=range]{width:100%;margin-bottom:8px;accent-color:#58a6ff;}
.ctrl-btns{display:flex;gap:6px;margin-top:4px;}
.ctrl-btn{flex:1;padding:5px;border:none;border-radius:6px;cursor:pointer;font-size:10px;font-weight:600;}
.ctrl-btn.reset{background:rgba(100,160,255,0.15);color:rgba(200,220,255,0.8);}
.ctrl-btn.export{background:rgba(80,160,255,0.3);color:#fff;}

/* Stats */
.stats{position:fixed;bottom:16px;left:16px;background:rgba(10,14,26,0.85);backdrop-filter:blur(12px);border:1px solid rgba(100,160,255,0.15);border-radius:10px;padding:12px 14px;color:rgba(200,220,255,0.8);font-size:10px;z-index:50;}
.stats-num{font-size:28px;font-weight:700;color:rgba(100,180,255,0.9);line-height:1;}
</style>
</head>
<body>
<canvas id="stars"></canvas>
<canvas id="graph"></canvas>

<!-- Preview panel -->
<div class="preview-panel" id="preview">
  <div class="preview-header" id="preview-header">
    <span class="preview-title" id="preview-title"></span>
    <button class="preview-btn" id="btn-collapse" title="Collapse" style="font-size:11px;">−</button>
    <button class="preview-btn" id="btn-expand" title="Expand" style="font-size:11px;">⤢</button>
    <button class="preview-btn" id="btn-close" title="Close" style="font-size:11px;">✕</button>
  </div>
  <div class="preview-body" id="preview-body"></div>
</div>

<!-- Stats -->
<div class="stats">
  <div style="color:rgba(100,180,255,0.4);text-transform:uppercase;letter-spacing:1px;font-size:9px;">Nodes</div>
  <div class="stats-num" id="node-count">0</div>
</div>

<!-- Controls -->
<div class="ctrl">
  <h3>Display Engine</h3>
  <div class="ctrl-row"><span>Gravity</span><span id="grav-val">0.012</span></div>
  <input type="range" id="gravity" min="0" max="0.05" step="0.001" value="0.012">
  <div class="ctrl-row"><span>Link Distance</span><span id="link-val">160px</span></div>
  <input type="range" id="linkDist" min="50" max="400" step="10" value="160">
  <div class="ctrl-row"><span>Repulsion</span><span id="rep-val">4.0k</span></div>
  <input type="range" id="repulsion" min="500" max="10000" step="100" value="4000">
  <div class="ctrl-btns">
    <button class="ctrl-btn reset" onclick="resetView()">Reset</button>
    <button class="ctrl-btn export" onclick="exportSVG()">Export SVG</button>
  </div>
</div>

<script>
const nodes = [\(nodesJSON)];
const edges = [\(edgesJSON)];
""" + buildScript() + """
</script>
</body></html>
"""
    }

    private func buildScript() -> String {
        """
// === SETUP ===
const starsCanvas = document.getElementById('stars');
const starsCtx = starsCanvas.getContext('2d');
const canvas = document.getElementById('graph');
const ctx = canvas.getContext('2d');
let W, H, dpr;

function resize() {
  dpr = window.devicePixelRatio || 1;
  W = window.innerWidth; H = window.innerHeight;
  starsCanvas.width = W * dpr; starsCanvas.height = H * dpr;
  canvas.width = W * dpr; canvas.height = H * dpr;
  starsCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}
resize();
window.addEventListener('resize', resize);

// === STARS BACKGROUND ===
const stars = Array.from({length: 200}, () => ({
  x: Math.random() * W, y: Math.random() * H,
  r: Math.random() * 1.2 + 0.3,
  a: Math.random(), speed: Math.random() * 0.003 + 0.001,
  phase: Math.random() * Math.PI * 2
}));

function drawStars(t) {
  starsCtx.clearRect(0, 0, W, H);
  // Subtle nebula gradient
  const g = starsCtx.createRadialGradient(W*0.3, H*0.4, 0, W*0.3, H*0.4, W*0.6);
  g.addColorStop(0, 'rgba(20,40,80,0.15)');
  g.addColorStop(0.5, 'rgba(10,20,50,0.08)');
  g.addColorStop(1, 'transparent');
  starsCtx.fillStyle = g;
  starsCtx.fillRect(0, 0, W, H);

  const g2 = starsCtx.createRadialGradient(W*0.7, H*0.6, 0, W*0.7, H*0.6, W*0.4);
  g2.addColorStop(0, 'rgba(50,20,60,0.1)');
  g2.addColorStop(1, 'transparent');
  starsCtx.fillStyle = g2;
  starsCtx.fillRect(0, 0, W, H);

  stars.forEach(s => {
    const twinkle = 0.4 + 0.6 * (0.5 + 0.5 * Math.sin(t * s.speed * 2 + s.phase));
    starsCtx.beginPath();
    starsCtx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
    starsCtx.fillStyle = `rgba(180,200,255,${twinkle * 0.7})`;
    starsCtx.fill();
  });
}

// === PHYSICS ===
let params = { gravity: 0.012, linkDist: 160, repulsion: 4000 };
const cam = { x: 0, y: 0, zoom: 1 };

// Palette: cosmic colors
const PALETTE = ['#58a6ff','#7ee787','#d2a8ff','#ff7b72','#ffa657','#79c0ff','#f778ba','#3fb950','#d29922','#a5d6ff'];
const _folders = [...new Set(nodes.map(n => n.folder))].filter(f => f).sort();
const folderColor = {}; _folders.forEach((f,i) => { folderColor[f] = PALETTE[i % PALETTE.length]; });

nodes.forEach(n => {
  n.x = W/2 + (Math.random()-0.5) * Math.min(W, 500);
  n.y = H/2 + (Math.random()-0.5) * Math.min(H, 400);
  n.vx = 0; n.vy = 0; n.degree = 0;
  n.color = folderColor[n.folder] || '#58a6ff';
  n.pulsePhase = Math.random() * Math.PI * 2;
});
edges.forEach(e => { nodes[e.source].degree++; nodes[e.target].degree++; });
const connected = new Set(); edges.forEach(e => { connected.add(e.source); connected.add(e.target); });
document.getElementById('node-count').textContent = nodes.length;

function physics(dt) {
  const damping = 0.92;
  // Repulsion (Barnes-Hut would be better for large graphs)
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
    let force = (dist - params.linkDist) * 0.008;
    let fx = (dx/dist)*force, fy = (dy/dist)*force;
    s.vx += fx; s.vy += fy; t.vx -= fx; t.vy -= fy;
  });
  // Gravity + damping (skip pinned nodes)
  nodes.forEach(n => {
    if (n.pinned) return;
    n.vx += (W/2 - n.x) * params.gravity;
    n.vy += (H/2 - n.y) * params.gravity;
    n.vx *= damping; n.vy *= damping;
    n.x += n.vx; n.y += n.vy;
  });
}

// === RENDERING ===
let hoveredNode = null;
let filterState = { search: '', orphan: false, folder: '' };

function nodeRadius(n) { return Math.max(4, Math.min(16, 3 + n.degree * 3)); }

function worldToScreen(wx, wy) {
  return { x: (wx - cam.x) * cam.zoom + W/2, y: (wy - cam.y) * cam.zoom + H/2 };
}
function screenToWorld(sx, sy) {
  return { x: (sx - W/2) / cam.zoom + cam.x, y: (sy - H/2) / cam.zoom + cam.y };
}

function isFiltered(n) {
  const { search, orphan, folder } = filterState;
  if (search && !n.label.toLowerCase().includes(search.toLowerCase())) return true;
  if (orphan && n.degree > 0) return true;
  if (folder && n.folder !== folder) return true;
  return false;
}

function draw(t) {
  ctx.clearRect(0, 0, W, H);
  ctx.save();
  ctx.translate(W/2, H/2);
  ctx.scale(cam.zoom, cam.zoom);
  ctx.translate(-cam.x, -cam.y);

  // Edges
  edges.forEach(e => {
    const s = nodes[e.source], t2 = nodes[e.target];
    const filt = isFiltered(s) && isFiltered(t2);
    const alpha = filt ? 0.03 : (hoveredNode && (hoveredNode.id === s.id || hoveredNode.id === t2.id) ? 0.6 : 0.15);
    ctx.beginPath();
    ctx.moveTo(s.x, s.y); ctx.lineTo(t2.x, t2.y);
    ctx.strokeStyle = `rgba(100,160,255,${alpha})`;
    ctx.lineWidth = hoveredNode && (hoveredNode.id === s.id || hoveredNode.id === t2.id) ? 1.5 : 0.8;
    ctx.stroke();
  });

  // Nodes
  nodes.forEach(n => {
    const filt = isFiltered(n);
    const r = nodeRadius(n);
    const pulse = 1 + 0.08 * Math.sin(t * 0.002 + n.pulsePhase);
    const drawR = r * pulse;
    const alpha = filt ? 0.06 : 1;
    const isHovered = hoveredNode && hoveredNode.id === n.id;
    const color = connected.has(n.id) ? n.color : 'rgba(100,130,170,0.5)';
    const p = { x: n.x, y: n.y };

    // Glow
    if (!filt && connected.has(n.id)) {
      const glow = ctx.createRadialGradient(p.x, p.y, drawR * 0.5, p.x, p.y, drawR * 3);
      glow.addColorStop(0, color.replace(')', ',0.15)').replace('rgb', 'rgba'));
      glow.addColorStop(1, 'transparent');
      ctx.fillStyle = glow;
      ctx.beginPath(); ctx.arc(p.x, p.y, drawR * 3, 0, Math.PI * 2); ctx.fill();
    }

    // Core
    ctx.beginPath(); ctx.arc(p.x, p.y, drawR, 0, Math.PI * 2);
    ctx.fillStyle = filt ? `rgba(60,70,90,${alpha})` : color;
    ctx.globalAlpha = alpha;
    ctx.fill();

    // Bright center
    if (!filt) {
      ctx.beginPath(); ctx.arc(p.x, p.y, drawR * 0.4, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(255,255,255,0.3)';
      ctx.fill();
    }

    // Hover ring
    if (isHovered) {
      ctx.beginPath(); ctx.arc(p.x, p.y, drawR + 4, 0, Math.PI * 2);
      ctx.strokeStyle = color; ctx.lineWidth = 1.5; ctx.globalAlpha = 0.6; ctx.stroke();
    }
    ctx.globalAlpha = 1;

    // Label
    if (!filt && (cam.zoom > 0.6 || isHovered || n.degree > 0)) {
      ctx.font = `${isHovered ? 'bold ' : ''}${Math.max(9, 11 / Math.max(cam.zoom, 0.5))}px -apple-system,sans-serif`;
      ctx.textAlign = 'center';
      ctx.fillStyle = filt ? 'rgba(100,130,170,0.1)' : `rgba(200,220,255,${isHovered ? 0.95 : 0.7})`;
      ctx.fillText(n.label, p.x, p.y - drawR - 6);
    }
  });

  ctx.restore();
}

// === ANIMATION LOOP ===
let lastTime = 0;
function loop(t) {
  if (!lastTime) lastTime = t;
  const dt = Math.min(t - lastTime, 32);
  lastTime = t;
  physics(dt);
  drawStars(t);
  draw(t);
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);

// === INTERACTION ===
let drag = { active: false, node: null, sx: 0, sy: 0, camSX: 0, camSY: 0 };

function getNodeAt(sx, sy) {
  const w = screenToWorld(sx, sy);
  for (let i = nodes.length - 1; i >= 0; i--) {
    const n = nodes[i], r = nodeRadius(n) + 4;
    const dx = n.x - w.x, dy = n.y - w.y;
    if (dx*dx + dy*dy < (r/cam.zoom)*(r/cam.zoom) * 4) return n;
  }
  return null;
}

canvas.addEventListener('mousedown', ev => {
  const n = getNodeAt(ev.offsetX, ev.offsetY);
  drag.active = true; drag.sx = ev.clientX; drag.sy = ev.clientY;
  if (n) { drag.node = n; } else { drag.node = null; drag.camSX = cam.x; drag.camSY = cam.y; }
});

window.addEventListener('mousemove', ev => {
  // Hover detection
  const n = getNodeAt(ev.offsetX, ev.offsetY);
  if (n !== hoveredNode) {
    hoveredNode = n;
    canvas.style.cursor = n ? 'pointer' : 'grab';
    clearTimeout(hoverTimer);
    if (n) {
      hoverTimer = setTimeout(() => showPreview(n, ev.clientX, ev.clientY), 3000);
    }
  }
  if (!drag.active) return;
  if (drag.node) {
    const scale = 1 / cam.zoom;
    drag.node.x += (ev.clientX - drag.sx) * scale;
    drag.node.y += (ev.clientY - drag.sy) * scale;
    drag.node.vx = 0; drag.node.vy = 0;
    drag.sx = ev.clientX; drag.sy = ev.clientY;
  } else {
    cam.x = drag.camSX - (ev.clientX - drag.sx) / cam.zoom;
    cam.y = drag.camSY - (ev.clientY - drag.sy) / cam.zoom;
  }
});

window.addEventListener('mouseup', () => {
  if (drag.node) drag.node.pinned = true;
  drag.active = false; drag.node = null;
});

canvas.addEventListener('wheel', ev => {
  ev.preventDefault();
  const factor = ev.deltaY > 0 ? 0.92 : 1.08;
  const w = screenToWorld(ev.offsetX, ev.offsetY);
  cam.zoom *= factor;
  cam.zoom = Math.max(0.1, Math.min(5, cam.zoom));
  const w2 = screenToWorld(ev.offsetX, ev.offsetY);
  cam.x -= w2.x - w.x; cam.y -= w2.y - w.y;
}, {passive: false});

canvas.addEventListener('dblclick', ev => {
  const n = getNodeAt(ev.offsetX, ev.offsetY);
  if (n) {
    if (n.pinned) { n.pinned = false; }
    else { window.webkit.messageHandlers.graphHandler.postMessage(n.path); }
  }
});

// === HOVER PREVIEW PANEL ===
let hoverTimer = null;
const panel = document.getElementById('preview');
const panelTitle = document.getElementById('preview-title');
const panelBody = document.getElementById('preview-body');
let panelExpanded = false;

let _secId = 0;
function renderMd(text) {
  if (!text) return '<em style="opacity:0.5">No content</em>';
  let s = text.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  // Fenced code blocks - placeholder to protect them
  const codeBlocks = [];
  s = s.replace(/```(\\w*)\\n([\\s\\S]*?)```/g, function(m, lang, code) {
    codeBlocks.push('<pre><code>' + code.trim() + '</code></pre>');
    return '%%CODE' + (codeBlocks.length-1) + '%%';
  });
  // Inline code
  s = s.replace(/`([^`]+)`/g, '<code>$1</code>');
  // Blockquotes
  s = s.replace(/^&gt; (.+)/gm, '<blockquote>$1</blockquote>');
  // Merge adjacent blockquotes
  s = s.replace(/<\\/blockquote>\\n<blockquote>/g, '<br>');
  // Horizontal rules
  s = s.replace(/^---+$/gm, '<hr>');
  // Bullet lists FIRST (before bold/italic can eat the *)
  s = s.replace(/^\\s{0,3}[\\*\\-] (.+)/gm, '<li>$1</li>');
  // Numbered lists
  s = s.replace(/^\\s{0,3}(\\d+)[\\.\\\\.] (.+)/gm, '<li>$2</li>');
  // Collapsible headers
  s = s.replace(/^### (.+)/gm, function(m, t) {
    const id = 'sec' + (_secId++);
    return '</div><h3 class="collapse-hdr" onclick="toggleSec(\\''+id+'\\')">'+t+'</h3><div class="collapse-section" id="'+id+'">';
  });
  s = s.replace(/^## (.+)/gm, function(m, t) {
    const id = 'sec' + (_secId++);
    return '</div><h2 class="collapse-hdr" onclick="toggleSec(\\''+id+'\\')">'+t+'</h2><div class="collapse-section" id="'+id+'">';
  });
  s = s.replace(/^# (.+)/gm, function(m, t) {
    const id = 'sec' + (_secId++);
    return '</div><h1 class="collapse-hdr" onclick="toggleSec(\\''+id+'\\')">'+t+'</h1><div class="collapse-section" id="'+id+'">';
  });
  // Bold and italic
  s = s.replace(/\\*\\*(.+?)\\*\\*/g, '<strong>$1</strong>');
  s = s.replace(/\\*(.+?)\\*/g, '<em>$1</em>');
  // Wiki-links
  s = s.replace(/\\[\\[(.+?)\\]\\]/g, '<a>$1</a>');
  // Clean stray ## markers inside list items
  s = s.replace(/<li>#{1,6} /g, '<li>');
  // Newlines to <br>
  s = s.replace(/\\n/g, '<br>');
  // Clean leading empty div
  s = s.replace(/^<\\/div>/, '');
  s += '</div>';
  // Restore code blocks
  codeBlocks.forEach(function(block, i) { s = s.replace('%%CODE'+i+'%%', block); });
  return s;
}
function toggleSec(id) {
  const el = document.getElementById(id);
  const hdr = el.previousElementSibling;
  if (el) { el.classList.toggle('hidden'); }
  if (hdr) { hdr.classList.toggle('collapsed'); }
}

function showPreview(n, mx, my) {
  panelTitle.textContent = n.label;
  panelBody.innerHTML = renderMd(n.preview);
  panelBody.classList.toggle('expanded', panelExpanded);
  panel.classList.toggle('expanded-panel', panelExpanded);
  panel.style.display = 'block';
  const pw = panelExpanded ? 500 : 340;
  let px = Math.min(mx + 16, W - pw - 10), py = Math.min(my - 20, H - 300);
  panel.style.left = Math.max(10, px) + 'px'; panel.style.top = Math.max(10, py) + 'px';
}

// Allow scrolling inside preview panel
panel.addEventListener('wheel', function(e) { e.stopPropagation(); }, {passive: true});
let panelCollapsed = false;
document.getElementById('btn-close').addEventListener('click', () => { panel.style.display = 'none'; });
document.getElementById('btn-collapse').addEventListener('click', () => {
  panelCollapsed = !panelCollapsed;
  panel.classList.toggle('collapsed-panel', panelCollapsed);
  document.getElementById('btn-collapse').textContent = panelCollapsed ? '+' : '\\u2212';
});
document.getElementById('btn-expand').addEventListener('click', () => {
  panelExpanded = !panelExpanded;
  panelCollapsed = false;
  panel.classList.remove('collapsed-panel');
  panelBody.classList.toggle('expanded', panelExpanded);
  panel.classList.toggle('expanded-panel', panelExpanded);
  document.getElementById('btn-expand').textContent = panelExpanded ? '\\u2198' : '\\u2922';
  document.getElementById('btn-collapse').textContent = '\\u2212';
});

// Draggable panel header
let panelDrag = { active: false, sx: 0, sy: 0, ox: 0, oy: 0 };
document.getElementById('preview-header').addEventListener('mousedown', ev => {
  panelDrag.active = true; panelDrag.sx = ev.clientX; panelDrag.sy = ev.clientY;
  panelDrag.ox = panel.offsetLeft; panelDrag.oy = panel.offsetTop;
  ev.preventDefault();
});
window.addEventListener('mousemove', ev => {
  if (!panelDrag.active) return;
  panel.style.left = (panelDrag.ox + ev.clientX - panelDrag.sx) + 'px';
  panel.style.top = (panelDrag.oy + ev.clientY - panelDrag.sy) + 'px';
});
window.addEventListener('mouseup', () => { panelDrag.active = false; });

// === CONTROLS ===
document.getElementById('gravity').addEventListener('input', e => {
  params.gravity = parseFloat(e.target.value);
  document.getElementById('grav-val').textContent = params.gravity.toFixed(3);
});
document.getElementById('linkDist').addEventListener('input', e => {
  params.linkDist = parseInt(e.target.value);
  document.getElementById('link-val').textContent = params.linkDist + 'px';
});
document.getElementById('repulsion').addEventListener('input', e => {
  params.repulsion = parseInt(e.target.value);
  document.getElementById('rep-val').textContent = (params.repulsion >= 1000 ? (params.repulsion/1000).toFixed(1)+'k' : params.repulsion);
});

function resetView() {
  cam.x = W/2; cam.y = H/2; cam.zoom = 1;
  nodes.forEach(n => { n.x = W/2+(Math.random()-0.5)*300; n.y = H/2+(Math.random()-0.5)*300; n.vx=0; n.vy=0; n.pinned=false; });
}

function applyGraphFilter(search, orphanOnly, folderFilter) {
  filterState = { search, orphan: orphanOnly, folder: folderFilter };
}

// === SVG EXPORT ===
function exportSVG() {
  // Build a clean SVG from current state
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  nodes.forEach(n => {
    const r = nodeRadius(n) + 20;
    minX = Math.min(minX, n.x - r); minY = Math.min(minY, n.y - r);
    maxX = Math.max(maxX, n.x + r); maxY = Math.max(maxY, n.y + r);
  });
  const pad = 60;
  const vw = maxX - minX + pad*2, vh = maxY - minY + pad*2;
  let svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${minX-pad} ${minY-pad} ${vw} ${vh}" width="${Math.round(vw)}" height="${Math.round(vh)}">`;
  svg += `<rect x="${minX-pad}" y="${minY-pad}" width="${vw}" height="${vh}" fill="#05080f"/>`;

  // Edges
  edges.forEach(e => {
    const s = nodes[e.source], t = nodes[e.target];
    svg += `<line x1="${s.x}" y1="${s.y}" x2="${t.x}" y2="${t.y}" stroke="rgba(100,160,255,0.2)" stroke-width="0.8"/>`;
  });

  // Nodes
  nodes.forEach(n => {
    const r = nodeRadius(n);
    const color = connected.has(n.id) ? n.color : '#667';
    svg += `<circle cx="${n.x}" cy="${n.y}" r="${r}" fill="${color}"/>`;
    svg += `<circle cx="${n.x}" cy="${n.y}" r="${r*0.4}" fill="rgba(255,255,255,0.25)"/>`;
    svg += `<text x="${n.x}" y="${n.y - r - 6}" text-anchor="middle" fill="rgba(200,220,255,0.7)" font-family="-apple-system,sans-serif" font-size="11">${n.label.replace(/&/g,'&amp;').replace(/</g,'&lt;')}</text>`;
  });

  svg += '</svg>';
  window.webkit.messageHandlers.exportHandler.postMessage('<?xml version="1.0"?>' + svg);
}

// Center camera on graph
cam.x = W/2; cam.y = H/2;
"""
    }
}
