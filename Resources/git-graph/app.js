// Git Graph Renderer
// Entry points called from Swift via evaluateJavaScript:
//   window.updateGraph(jsonString) — render commit graph
//   window.applyTheme(hexColor, isDark) — update theme colors

(function () {
  "use strict";

  var SVG_NS = "http://www.w3.org/2000/svg";

  // Lane colors — cycled for branch lines
  var LANE_COLORS = [
    "#e06c75", "#98c379", "#e5c07b", "#61afef",
    "#c678dd", "#56b6c2", "#d19a66", "#be5046"
  ];

  var ROW_HEIGHT = 24;
  var LANE_WIDTH = 12;
  var LEFT_PADDING = 10;
  var NODE_RADIUS = 3;

  // -------------------------------------------------------
  // Theme
  // -------------------------------------------------------

  window.applyTheme = function (hexColor, isDark) {
    var root = document.documentElement;
    root.style.setProperty("--graph-bg", hexColor);

    if (isDark) {
      root.style.setProperty("--commit-hash-color", "#569cd6");
      root.style.setProperty("--message-color", "#d4d4d4");
      root.style.setProperty("--secondary-color", "#808080");
      root.style.setProperty("--accent-color", "#0091FF");
      root.style.setProperty("--ref-branch-bg", "rgba(0,145,255,0.15)");
      root.style.setProperty("--ref-branch-border", "#0091FF");
      root.style.setProperty("--ref-tag-border", "#808080");
    } else {
      root.style.setProperty("--commit-hash-color", "#0550ae");
      root.style.setProperty("--message-color", "#1f2328");
      root.style.setProperty("--secondary-color", "#656d76");
      root.style.setProperty("--accent-color", "#0088FF");
      root.style.setProperty("--ref-branch-bg", "rgba(0,136,255,0.1)");
      root.style.setProperty("--ref-branch-border", "#0088FF");
      root.style.setProperty("--ref-tag-border", "#656d76");
    }
  };

  // -------------------------------------------------------
  // JS→Swift bridge
  // -------------------------------------------------------

  function postMessage(action, data) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.gitGraph) {
      var msg = { action: action };
      if (data) {
        for (var key in data) {
          if (data.hasOwnProperty(key)) msg[key] = data[key];
        }
      }
      window.webkit.messageHandlers.gitGraph.postMessage(msg);
    }
  }

  // -------------------------------------------------------
  // Context menu
  // -------------------------------------------------------

  function showContextMenu(x, y, hash, refs) {
    hideContextMenu();
    var menu = document.createElement("div");
    menu.className = "context-menu";
    menu.style.left = x + "px";
    menu.style.top = y + "px";

    var copyItem = document.createElement("div");
    copyItem.className = "context-menu-item";
    copyItem.textContent = "Copy SHA";
    copyItem.onclick = function () {
      postMessage("copyHash", { hash: hash });
      hideContextMenu();
    };
    menu.appendChild(copyItem);

    var openItem = document.createElement("div");
    openItem.className = "context-menu-item";
    openItem.textContent = "Open in Browser";
    openItem.onclick = function () {
      postMessage("openInBrowser", { hash: hash });
      hideContextMenu();
    };
    menu.appendChild(openItem);

    if (refs && refs.length > 0) {
      for (var i = 0; i < refs.length; i++) {
        var ref = refs[i];
        if (ref.type !== "tag") {
          (function (branchName) {
            var checkoutItem = document.createElement("div");
            checkoutItem.className = "context-menu-item";
            checkoutItem.textContent = "Checkout " + branchName;
            checkoutItem.onclick = function () {
              postMessage("checkoutBranch", { branch: branchName });
              hideContextMenu();
            };
            menu.appendChild(checkoutItem);
          })(ref.name);
        }
      }
    }

    document.body.appendChild(menu);
    setTimeout(function () {
      document.addEventListener("click", hideContextMenu, { once: true });
    }, 0);
  }

  function hideContextMenu() {
    var existing = document.querySelector(".context-menu");
    if (existing) existing.remove();
  }

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") hideContextMenu();
  });

  // -------------------------------------------------------
  // Lane assignment (greedy)
  // -------------------------------------------------------

  function assignLanes(commits) {
    // Build lookup: hash → index
    var hashToIndex = {};
    for (var i = 0; i < commits.length; i++) {
      hashToIndex[commits[i].hash] = i;
    }

    // activeLanes[laneIndex] = hash of commit that "owns" this lane
    var activeLanes = [];
    var commitLanes = new Array(commits.length);
    // parentLanes[i] = array of { parentIndex, lane } for drawing lines
    var parentLanes = new Array(commits.length);

    for (var ci = 0; ci < commits.length; ci++) {
      var commit = commits[ci];
      var parents = commit.parents || [];
      var myLane = -1;

      // Check if this commit is already expected in a lane
      for (var li = 0; li < activeLanes.length; li++) {
        if (activeLanes[li] === commit.hash) {
          myLane = li;
          break;
        }
      }

      // If not in any lane, take the first free one
      if (myLane === -1) {
        myLane = firstFreeLane(activeLanes);
        activeLanes[myLane] = commit.hash;
      }

      commitLanes[ci] = myLane;

      // Process parents
      var pLanes = [];
      if (parents.length > 0) {
        // First parent continues in the same lane
        activeLanes[myLane] = parents[0];
        pLanes.push({ parentHash: parents[0], lane: myLane });

        // Additional parents (merge) get their own lanes if not already active
        for (var pi = 1; pi < parents.length; pi++) {
          var pHash = parents[pi];
          var pLane = findLane(activeLanes, pHash);
          if (pLane === -1) {
            pLane = firstFreeLane(activeLanes);
            activeLanes[pLane] = pHash;
          }
          pLanes.push({ parentHash: pHash, lane: pLane });
        }
      } else {
        // Root commit — free the lane
        activeLanes[myLane] = null;
      }

      parentLanes[ci] = pLanes;
    }

    return { commitLanes: commitLanes, parentLanes: parentLanes, maxLane: activeLanes.length };
  }

  function firstFreeLane(lanes) {
    for (var i = 0; i < lanes.length; i++) {
      if (lanes[i] === null || lanes[i] === undefined) return i;
    }
    return lanes.length;
  }

  function findLane(lanes, hash) {
    for (var i = 0; i < lanes.length; i++) {
      if (lanes[i] === hash) return i;
    }
    return -1;
  }

  // -------------------------------------------------------
  // SVG rendering
  // -------------------------------------------------------

  function laneX(lane) {
    return LEFT_PADDING + lane * LANE_WIDTH + LANE_WIDTH / 2;
  }

  function rowY(index) {
    return index * ROW_HEIGHT + ROW_HEIGHT / 2;
  }

  function laneColor(lane) {
    return LANE_COLORS[lane % LANE_COLORS.length];
  }

  function createSvg(commits, layout) {
    var svgWidth = (layout.maxLane + 1) * LANE_WIDTH + LEFT_PADDING * 2;
    var svgHeight = commits.length * ROW_HEIGHT;

    var svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("width", svgWidth);
    svg.setAttribute("height", svgHeight);
    svg.setAttribute("class", "graph-svg");

    // Draw branch lines first (behind nodes)
    for (var i = 0; i < commits.length; i++) {
      var pLanes = layout.parentLanes[i];
      var myLane = layout.commitLanes[i];

      for (var p = 0; p < pLanes.length; p++) {
        var parentHash = pLanes[p].parentHash;
        var parentLane = pLanes[p].lane;

        // Find parent row index
        var parentIndex = -1;
        for (var j = i + 1; j < commits.length; j++) {
          if (commits[j].hash === parentHash) {
            parentIndex = j;
            break;
          }
        }
        if (parentIndex === -1) continue;

        var x1 = laneX(myLane);
        var y1 = rowY(i);
        var x2 = laneX(parentLane);
        var y2 = rowY(parentIndex);

        var path = document.createElementNS(SVG_NS, "path");
        var color = laneColor(p === 0 ? myLane : parentLane);

        if (myLane === parentLane) {
          // Straight line
          path.setAttribute("d", "M" + x1 + "," + y1 + " L" + x2 + "," + y2);
        } else {
          // Bezier curve
          var midY = (y1 + y2) / 2;
          path.setAttribute("d",
            "M" + x1 + "," + y1 +
            " C" + x1 + "," + midY +
            " " + x2 + "," + midY +
            " " + x2 + "," + y2
          );
        }

        path.setAttribute("stroke", color);
        svg.appendChild(path);
      }
    }

    // Draw commit nodes on top
    for (var ni = 0; ni < commits.length; ni++) {
      var nodeLane = layout.commitLanes[ni];
      var circle = document.createElementNS(SVG_NS, "circle");
      circle.setAttribute("cx", laneX(nodeLane));
      circle.setAttribute("cy", rowY(ni));
      circle.setAttribute("r", NODE_RADIUS);
      circle.setAttribute("fill", laneColor(nodeLane));
      circle.setAttribute("stroke", laneColor(nodeLane));
      svg.appendChild(circle);
    }

    return svg;
  }

  // -------------------------------------------------------
  // Commit row DOM
  // -------------------------------------------------------

  function createRefLabels(refs) {
    var frag = document.createDocumentFragment();
    if (!refs || refs.length === 0) return frag;

    for (var i = 0; i < refs.length; i++) {
      var ref = refs[i];
      var span = document.createElement("span");
      span.className = "ref-label";
      span.textContent = ref.name;

      if (ref.type === "tag") {
        span.classList.add("ref-tag");
      } else {
        span.classList.add("ref-branch");
        if (ref.isCurrent) {
          span.classList.add("current");
        }
      }
      frag.appendChild(span);
    }
    return frag;
  }

  function createCommitRows(commits) {
    var frag = document.createDocumentFragment();

    for (var i = 0; i < commits.length; i++) {
      var commit = commits[i];
      var row = document.createElement("div");
      row.className = "commit-row";
      row.setAttribute("data-hash", commit.hash);

      row.addEventListener("click", (function (commitHash) {
        return function () {
          postMessage("commitSelected", { hash: commitHash });
        };
      })(commit.hash));

      row.addEventListener("contextmenu", (function (commitHash, commitRefs) {
        return function (e) {
          e.preventDefault();
          showContextMenu(e.pageX, e.pageY, commitHash, commitRefs || []);
        };
      })(commit.hash, commit.refs));

      var hash = document.createElement("span");
      hash.className = "commit-hash";
      hash.textContent = commit.abbreviatedHash;
      row.appendChild(hash);

      row.appendChild(createRefLabels(commit.refs));

      var msg = document.createElement("span");
      msg.className = "commit-message";
      msg.textContent = commit.message;
      row.appendChild(msg);

      var meta = document.createElement("span");
      meta.className = "commit-meta";
      meta.textContent = commit.author + " \u00b7 " + commit.relativeDate;
      row.appendChild(meta);

      frag.appendChild(row);
    }

    return frag;
  }

  // -------------------------------------------------------
  // Main entry point
  // -------------------------------------------------------

  window.updateGraph = function (jsonString) {
    var container = document.getElementById("graph-container");
    var data;

    try {
      if (typeof jsonString === "string") {
        data = JSON.parse(jsonString);
      } else {
        data = jsonString;
      }
    } catch (e) {
      console.error("git-graph: JSON parse error:", e);
      container.innerHTML = '<div style="color:#f44;padding:12px">Failed to parse graph data</div>';
      return;
    }

    var commits = data.commits || [];

    // Map refs to their commits for context menu
    var refsByHash = {};
    if (data.refs) {
      for (var ri = 0; ri < data.refs.length; ri++) {
        var ref = data.refs[ri];
        if (!refsByHash[ref.hash]) refsByHash[ref.hash] = [];
        refsByHash[ref.hash].push(ref);
      }
    }
    for (var ci = 0; ci < commits.length; ci++) {
      commits[ci].refs = refsByHash[commits[ci].hash] || [];
    }

    if (commits.length === 0) return;

    container.innerHTML = "";

    // Layout
    var layout = assignLanes(commits);

    // Build graph + rows side by side
    var wrapper = document.createElement("div");
    wrapper.className = "graph-wrapper";

    // SVG column
    var svgCol = document.createElement("div");
    svgCol.className = "graph-svg-col";
    svgCol.appendChild(createSvg(commits, layout));
    wrapper.appendChild(svgCol);

    // Text column
    var textCol = document.createElement("div");
    textCol.className = "graph-text-col";
    textCol.appendChild(createCommitRows(commits));
    wrapper.appendChild(textCol);

    container.appendChild(wrapper);
  };
})();
