// graph.js — r2d3 script for Acute Metrics R Graph
// r2d3 provides: data, svg (D3 selection), width, height
// data shape: { nodes: [...], edges: [...], nof: [...], counts: {...} }

const typeColours = {
  domain: '#8dd3c7', subdomain: '#80b1d3', analysis_product: '#fdb462',
  metric: '#bebada', nhs_oversight_metric: '#fb8072', dataset: '#b3de69',
  source_system: '#fccde5', pathway: '#ccebc5', external_requirement: '#d9d9d9',
  role: '#bc80bd'
};

const typeShapes = {
  domain: 'box', analysis_product: 'box', nhs_oversight_metric: 'box',
  metric: 'box', source_system: 'hexagon', dataset: 'database',
  pathway: 'box', role: 'dot', external_requirement: 'box', subdomain: 'box'
};

const typeIcons = {
  analysis_product: '📄', metric: '📈', nhs_oversight_metric: '📈',
  dataset: '🗄️', source_system: '⚙️', domain: '🏥',
  pathway: '➡️', role: '👤', external_requirement: '📌'
};

let simulation = null;
let selectedId = null;

function displayType(node) {
  return node.type === 'nhs_oversight_metric' ? 'metric' : (node.type || 'unknown');
}

function nodeRadius(d) {
  if (d.nofMetric) return 24;
  return Math.max(13, Math.min(26, 10 + Math.sqrt(d.degree || 1) * 3));
}

function shapePath(d) {
  const r = nodeRadius(d);
  const shape = typeShapes[displayType(d)] || 'dot';
  if (shape === 'diamond')
    return `M0,${-r}L${r},0L0,${r}L${-r},0Z`;
  if (shape === 'hexagon') {
    const h = r * 0.9;
    return `M${-r*.75},${-h}L${r*.75},${-h}L${r},0L${r*.75},${h}L${-r*.75},${h}L${-r},0Z`;
  }
  if (shape === 'database')
    return `M${-r},${-r*.35}a${r},${r*.45} 0 1,0 ${r*2},0v${r*.9}a${r},${r*.45} 0 1,1 ${-r*2},0Z`;
  if (shape === 'box')
    return `M${-r*1.55},${-r}h${r*3.1}a8,8 0 0 1 8,8v${r*2-16}a8,8 0 0 1 -8,8h${-r*3.1}a8,8 0 0 1 -8,-8v${-r*2+16}a8,8 0 0 1 8,-8Z`;
  return `M0,${-r}a${r},${r} 0 1,0 0,${r*2}a${r},${r} 0 1,0 0,${-r*2}`;
}

function degreeMap(edges) {
  const d = {};
  for (const e of edges) {
    d[e.source] = (d[e.source] || 0) + 1;
    d[e.target] = (d[e.target] || 0) + 1;
  }
  return d;
}

r2d3.onRender(function(data, svgEl, width, height) {
  const nofSet  = new Set((data.nof || []).map(n => n.id));
  const degrees = degreeMap(data.edges || []);

  const graphNodes = (data.nodes || []).map(n => ({
    ...n,
    degree:    degrees[n.id] || 1,
    nofMetric: n.type === 'nhs_oversight_metric' || nofSet.has(n.id)
  }));

  const graphEdges = (data.edges || []).map((e, i) => ({
    ...e,
    _id: `${e.source}->${e.target}:${e.type}:${i}`
  }));

  // Clear and size SVG
  svgEl.selectAll('*').remove();
  svgEl.attr('width', width).attr('height', height)
       .style('background', 'radial-gradient(circle at 15% 20%, #ffffff, #f7fbff 35%, #edf5ff)');

  // Arrow markers
  const defs = svgEl.append('defs');
  [['arrow', '#64748b'], ['arrow-red', '#dc2626']].forEach(([id, fill]) => {
    defs.append('marker')
      .attr('id', id).attr('viewBox', '0 -5 10 10')
      .attr('refX', 18).attr('refY', 0)
      .attr('markerWidth', 6).attr('markerHeight', 6).attr('orient', 'auto')
      .append('path').attr('d', 'M0,-5L10,0L0,5').attr('fill', fill);
  });

  // Zoom
  const zoom = d3.zoom()
    .scaleExtent([0.15, 4])
    .on('zoom', event => zoomLayer.attr('transform', event.transform));
  svgEl.call(zoom);

  const zoomLayer = svgEl.append('g');

  // Links
  const link = zoomLayer.append('g').selectAll('path')
    .data(graphEdges).join('path')
    .attr('fill', 'none')
    .attr('opacity', 0.62)
    .attr('cursor', 'pointer')
    .attr('stroke', d => d.type === 'maps_to_framework_metric' ? '#dc2626' : '#64748b')
    .attr('stroke-width', d => d.type === 'maps_to_framework_metric' ? 2 : 1.1)
    .attr('marker-end', d => `url(#${d.type === 'maps_to_framework_metric' ? 'arrow-red' : 'arrow'})`);

  link.append('title').text(d => `${d.type}: ${d.description || ''}`);

  // Nodes
  const node = zoomLayer.append('g').selectAll('g')
    .data(graphNodes).join('g')
    .attr('cursor', 'pointer')
    .on('click', (event, d) => {
      event.stopPropagation();
      selectedId = d.id;
      updateSelection();
      if (typeof Shiny !== 'undefined')
        Shiny.setInputValue('clicked_node', d.id, { priority: 'event' });
    })
    .call(d3.drag()
      .on('start', (e) => { if (!e.active) simulation.alphaTarget(0.3).restart(); e.subject.fx = e.subject.x; e.subject.fy = e.subject.y; })
      .on('drag',  (e) => { e.subject.fx = e.x; e.subject.fy = e.y; })
      .on('end',   (e) => { if (!e.active) simulation.alphaTarget(0); e.subject.fx = null; e.subject.fy = null; }));

  node.append('path')
    .attr('d', shapePath)
    .attr('fill', d => typeColours[displayType(d)] || '#dbeafe')
    .attr('stroke', d => d.nofMetric ? '#dc2626' : '#475569')
    .attr('stroke-width', d => d.nofMetric ? 3 : 1.7)
    .attr('filter', 'drop-shadow(0 4px 6px rgba(15,23,42,.18))');

  node.append('text')
    .attr('text-anchor', 'middle')
    .attr('font-size', '16px')
    .attr('dominant-baseline', 'central')
    .attr('pointer-events', 'none')
    .attr('y', d => typeShapes[displayType(d)] === 'box' ? -2 : 4)
    .text(d => typeIcons[d.type] || typeIcons[displayType(d)] || '');

  node.append('text')
    .attr('text-anchor', 'middle')
    .attr('font-size', '12px')
    .attr('font-weight', '750')
    .attr('fill', '#0f172a')
    .attr('paint-order', 'stroke')
    .attr('stroke', 'rgba(255,255,255,.92)')
    .attr('stroke-width', '4px')
    .attr('stroke-linejoin', 'round')
    .attr('pointer-events', 'none')
    .attr('y', d => nodeRadius(d) + 17)
    .text(d => d.label || '');

  node.append('title').text(d =>
    `${displayType(d)}${d.nofMetric ? ' · NHS Oversight Framework metric' : ''}\n${d.description || ''}`);

  svgEl.on('click', () => { selectedId = null; updateSelection(); });

  function updateSelection() {
    node.select('path')
      .attr('stroke', d => d.id === selectedId ? '#111827' : (d.nofMetric ? '#dc2626' : '#475569'))
      .attr('stroke-width', d => d.id === selectedId ? 4 : (d.nofMetric ? 3 : 1.7));
  }

  // Force simulation
  if (simulation) simulation.stop();

  simulation = d3.forceSimulation(graphNodes)
    .force('link', d3.forceLink(graphEdges).id(d => d.id)
      .distance(d => d.type === 'maps_to_framework_metric' ? 150 : 205).strength(0.35))
    .force('charge', d3.forceManyBody().strength(-540))
    .force('center', d3.forceCenter(width / 2, height / 2))
    .force('collision', d3.forceCollide().radius(d => nodeRadius(d) + 44))
    .on('tick', () => {
      link.attr('d', d => {
        const sx = d.source.x, sy = d.source.y, tx = d.target.x, ty = d.target.y;
        const dr = Math.sqrt((tx - sx) ** 2 + (ty - sy) ** 2) * 1.25;
        return `M${sx},${sy}A${dr},${dr} 0 0,1 ${tx},${ty}`;
      });
      node.attr('transform', d => `translate(${d.x ?? 0},${d.y ?? 0})`);
    });
});

r2d3.onResize(function(width, height) {
  r2d3.svg.attr('width', width).attr('height', height);
  if (simulation)
    simulation.force('center', d3.forceCenter(width / 2, height / 2)).alpha(0.3).restart();
});
