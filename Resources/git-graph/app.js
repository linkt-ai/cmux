// Git Graph Renderer
// Entry points called from Swift via evaluateJavaScript:
//   window.updateGraph(jsonString) — render commit graph
//   window.applyTheme(hexColor, isDark) — update theme colors
//   window.showCommitDetail(jsonString) — show commit detail drawer
//   window.hideCommitDetail() — hide commit detail drawer

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

  // Commit lookup map — populated by updateGraph
  var commitsByHash = {};
  var selectedCommitHash = null;

  // -------------------------------------------------------
  // Color helpers
  // -------------------------------------------------------

  function hexToRgb(hex) {
    hex = hex.replace(/^#/, "");
    if (hex.length === 3) {
      hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
    }
    var num = parseInt(hex, 16);
    return { r: (num >> 16) & 255, g: (num >> 8) & 255, b: num & 255 };
  }

  function rgbToHex(r, g, b) {
    return "#" + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
  }

  function adjustBrightness(hex, percent) {
    var rgb = hexToRgb(hex);
    var factor = percent / 100;
    var r, g, b;
    if (factor > 0) {
      r = Math.min(255, Math.round(rgb.r + (255 - rgb.r) * factor));
      g = Math.min(255, Math.round(rgb.g + (255 - rgb.g) * factor));
      b = Math.min(255, Math.round(rgb.b + (255 - rgb.b) * factor));
    } else {
      var f = 1 + factor;
      r = Math.max(0, Math.round(rgb.r * f));
      g = Math.max(0, Math.round(rgb.g * f));
      b = Math.max(0, Math.round(rgb.b * f));
    }
    return rgbToHex(r, g, b);
  }

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
      root.style.setProperty("--ref-tag-bg", "rgba(128,128,128,0.1)");
      root.style.setProperty("--ref-tag-border", "#808080");
    } else {
      root.style.setProperty("--commit-hash-color", "#0550ae");
      root.style.setProperty("--message-color", "#1f2328");
      root.style.setProperty("--secondary-color", "#656d76");
      root.style.setProperty("--accent-color", "#0088FF");
      root.style.setProperty("--ref-branch-bg", "rgba(0,136,255,0.1)");
      root.style.setProperty("--ref-branch-border", "#0088FF");
      root.style.setProperty("--ref-tag-bg", "rgba(101,109,118,0.08)");
      root.style.setProperty("--ref-tag-border", "#656d76");
    }

    // Drawer theme properties
    var drawerBg = isDark ? adjustBrightness(hexColor, 12) : adjustBrightness(hexColor, -6.5);
    root.style.setProperty("--drawer-bg", drawerBg);
    root.style.setProperty("--separator-color", isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.1)");
    root.style.setProperty("--addition-color", isDark ? "#3fb950" : "#1a7f37");
    root.style.setProperty("--deletion-color", isDark ? "#f85149" : "#cf222e");
  };

  // -------------------------------------------------------
  // Commit detail drawer
  // -------------------------------------------------------

  window.showCommitDetail = function (jsonString) {
    var detail;
    try {
      if (typeof jsonString === "string") {
        detail = JSON.parse(jsonString);
      } else {
        detail = jsonString;
      }
    } catch (e) {
      console.error("git-graph: detail JSON parse error:", e);
      return;
    }

    var commit = commitsByHash[detail.hash];
    if (!commit) return;

    // Track selected commit
    selectedCommitHash = detail.hash;
    updateSelectedRow();

    // Reuse or create drawer
    var drawer = document.querySelector(".commit-detail-drawer");
    if (!drawer) {
      drawer = document.createElement("div");
      drawer.className = "commit-detail-drawer";
      document.body.appendChild(drawer);
    }

    // Build drawer content
    drawer.innerHTML = "";

    // Close button
    var closeBtn = document.createElement("button");
    closeBtn.className = "detail-close-btn";
    closeBtn.textContent = "\u00d7";
    closeBtn.onclick = function () { window.hideCommitDetail(); };
    drawer.appendChild(closeBtn);

    // Header: abbreviated hash
    var headerSection = document.createElement("div");
    headerSection.className = "detail-section";
    var headerHash = document.createElement("div");
    headerHash.className = "detail-header-hash";
    headerHash.textContent = commit.abbreviatedHash;
    headerSection.appendChild(headerHash);
    drawer.appendChild(headerSection);

    // Full hash (copyable)
    var hashSection = document.createElement("div");
    hashSection.className = "detail-section";
    var hashLabel = document.createElement("div");
    hashLabel.className = "detail-section-label";
    hashLabel.textContent = "SHA";
    hashSection.appendChild(hashLabel);
    var fullHash = document.createElement("div");
    fullHash.className = "detail-full-hash";
    fullHash.textContent = detail.hash;
    fullHash.onclick = function () {
      postMessage("copyHash", { hash: detail.hash });
      showCopiedToast(fullHash);
    };
    hashSection.appendChild(fullHash);
    drawer.appendChild(hashSection);

    // Author
    var authorSection = document.createElement("div");
    authorSection.className = "detail-section";
    var authorLabel = document.createElement("div");
    authorLabel.className = "detail-section-label";
    authorLabel.textContent = "AUTHOR";
    authorSection.appendChild(authorLabel);
    var author = document.createElement("div");
    author.className = "detail-author";
    author.textContent = commit.authorName + " <" + commit.authorEmail + ">";
    authorSection.appendChild(author);
    drawer.appendChild(authorSection);

    // Date
    var dateSection = document.createElement("div");
    dateSection.className = "detail-section";
    var dateLabel = document.createElement("div");
    dateLabel.className = "detail-section-label";
    dateLabel.textContent = "DATE";
    dateSection.appendChild(dateLabel);
    var dateDiv = document.createElement("div");
    dateDiv.className = "detail-date";
    var dateObj = new Date(commit.authorDate);
    var dateStr = isNaN(dateObj.getTime()) ? commit.authorDate :
      dateObj.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" }) +
      " \u00b7 " + formatRelativeDate(commit.authorDate);
    dateDiv.textContent = dateStr;
    dateSection.appendChild(dateDiv);
    drawer.appendChild(dateSection);

    // Message
    var msgSection = document.createElement("div");
    msgSection.className = "detail-section";
    var msgLabel = document.createElement("div");
    msgLabel.className = "detail-section-label";
    msgLabel.textContent = "MESSAGE";
    msgSection.appendChild(msgLabel);
    var msgDiv = document.createElement("div");
    msgDiv.className = "detail-message";
    var fullMsg = commit.fullMessage || commit.message || "";
    var msgLines = fullMsg.split("\n");
    if (msgLines.length > 0) {
      var subject = document.createElement("span");
      subject.className = "detail-message-subject";
      subject.textContent = msgLines[0];
      msgDiv.appendChild(subject);
      if (msgLines.length > 1) {
        msgDiv.appendChild(document.createTextNode("\n" + msgLines.slice(1).join("\n")));
      }
    }
    msgSection.appendChild(msgDiv);
    drawer.appendChild(msgSection);

    // Files
    var filesSection = document.createElement("div");
    filesSection.className = "detail-section detail-files-section";
    var filesLabel = document.createElement("div");
    filesLabel.className = "detail-section-label";
    filesLabel.textContent = "FILES";
    filesSection.appendChild(filesLabel);

    var files = detail.files || [];
    if (files.length === 0) {
      var noFiles = document.createElement("div");
      noFiles.className = "detail-files-summary";
      noFiles.textContent = "No file changes";
      filesSection.appendChild(noFiles);
    } else {
      var summary = document.createElement("div");
      summary.className = "detail-files-summary";
      summary.textContent = detail.totalFiles + (detail.totalFiles === 1 ? " file" : " files") +
        " changed, +" + detail.totalAdditions + " -" + detail.totalDeletions;
      filesSection.appendChild(summary);

      for (var i = 0; i < files.length; i++) {
        var file = files[i];
        var fileItem = document.createElement("div");
        fileItem.className = "detail-file-item";

        var filePath = document.createElement("span");
        filePath.className = "detail-file-path";
        filePath.textContent = file.path;
        filePath.title = file.path;
        fileItem.appendChild(filePath);

        if (file.additions === 0 && file.deletions === 0) {
          var binaryLabel = document.createElement("span");
          binaryLabel.className = "detail-file-additions";
          binaryLabel.textContent = "binary";
          fileItem.appendChild(binaryLabel);
        } else {
          var additions = document.createElement("span");
          additions.className = "detail-file-additions";
          additions.textContent = "+" + file.additions;
          fileItem.appendChild(additions);

          var deletions = document.createElement("span");
          deletions.className = "detail-file-deletions";
          deletions.textContent = "-" + file.deletions;
          fileItem.appendChild(deletions);
        }

        filesSection.appendChild(fileItem);
      }
    }
    drawer.appendChild(filesSection);

    // Action buttons
    var actions = document.createElement("div");
    actions.className = "detail-actions";

    var copyBtn2 = document.createElement("button");
    copyBtn2.className = "detail-action-btn";
    copyBtn2.setAttribute("data-action", "copyHash");
    copyBtn2.textContent = "Copy Hash";
    copyBtn2.onclick = function () {
      postMessage("copyHash", { hash: detail.hash });
      showCopiedToast(copyBtn2);
    };
    actions.appendChild(copyBtn2);

    var openBtn = document.createElement("button");
    openBtn.className = "detail-action-btn";
    openBtn.setAttribute("data-action", "openInBrowser");
    openBtn.textContent = "Open in Browser";
    openBtn.onclick = function () {
      postMessage("openInBrowser", { hash: detail.hash });
    };
    actions.appendChild(openBtn);

    drawer.appendChild(actions);

    // Animate open
    requestAnimationFrame(function () {
      drawer.classList.add("open");
    });

    // Shift graph container
    var container = document.getElementById("graph-container");
    if (container) container.style.marginRight = "320px";
  };

  window.hideCommitDetail = function () {
    var drawer = document.querySelector(".commit-detail-drawer");
    if (drawer) {
      drawer.classList.remove("open");
    }
    var container = document.getElementById("graph-container");
    if (container) container.style.marginRight = "";
    selectedCommitHash = null;
    updateSelectedRow();
  };

  function updateSelectedRow() {
    var rows = document.querySelectorAll(".commit-row");
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].getAttribute("data-hash") === selectedCommitHash) {
        rows[i].classList.add("selected");
      } else {
        rows[i].classList.remove("selected");
      }
    }
  }

  function showCopiedToast(anchorEl) {
    var existing = anchorEl.querySelector(".detail-copied-toast");
    if (existing) existing.remove();
    var toast = document.createElement("span");
    toast.className = "detail-copied-toast";
    toast.textContent = "Copied!";
    anchorEl.appendChild(toast);
    setTimeout(function () { toast.remove(); }, 1500);
  }

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
    if (e.key === "Escape") {
      hideContextMenu();
      var drawer = document.querySelector(".commit-detail-drawer.open");
      if (drawer) window.hideCommitDetail();
    }
  });

  // Click-outside to close drawer
  document.addEventListener("click", function (e) {
    var drawer = document.querySelector(".commit-detail-drawer.open");
    if (!drawer) return;
    // If click is inside the drawer, ignore
    if (drawer.contains(e.target)) return;
    // If click is on a commit row, let the row click handler manage it
    var row = e.target.closest(".commit-row");
    if (row) return;
    window.hideCommitDetail();
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
    // parentLanes[i] = array of { parentHash, lane, inWindow } for drawing lines
    var parentLanes = new Array(commits.length);

    for (var ci = 0; ci < commits.length; ci++) {
      var commit = commits[ci];
      var parents = commit.parents || [];
      var myLane = -1;

      // Check if this commit is already expected in a lane
      for (var li = 0; li < activeLanes.length; li++) {
        if (activeLanes[li] === commit.hash) {
          if (myLane === -1) {
            myLane = li;
          } else {
            // Duplicate lane pointing to same commit — free it
            activeLanes[li] = null;
          }
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
        var firstParentInWindow = hashToIndex.hasOwnProperty(parents[0]);
        // First parent continues in the same lane
        if (firstParentInWindow) {
          activeLanes[myLane] = parents[0];
        } else {
          // Parent is outside the window — free the lane
          activeLanes[myLane] = null;
        }
        pLanes.push({ parentHash: parents[0], lane: myLane, inWindow: firstParentInWindow });

        // Additional parents (merge) get their own lanes if not already active
        for (var pi = 1; pi < parents.length; pi++) {
          var pHash = parents[pi];
          var parentInWindow = hashToIndex.hasOwnProperty(pHash);
          if (parentInWindow) {
            var pLane = findLane(activeLanes, pHash);
            if (pLane === -1) {
              pLane = firstFreeLane(activeLanes);
              activeLanes[pLane] = pHash;
            }
            pLanes.push({ parentHash: pHash, lane: pLane, inWindow: true });
          } else {
            // Don't allocate a lane for parents outside the window
            pLanes.push({ parentHash: pHash, lane: myLane, inWindow: false });
          }
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
    // Build hash → index lookup for fast parent resolution
    var hashToIndex = {};
    for (var hi = 0; hi < commits.length; hi++) {
      hashToIndex[commits[hi].hash] = hi;
    }

    var svgWidth = (layout.maxLane + 1) * LANE_WIDTH + LEFT_PADDING * 2;
    var svgHeight = commits.length * ROW_HEIGHT;

    var svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("width", svgWidth);
    svg.setAttribute("height", svgHeight);
    svg.setAttribute("class", "graph-svg");

    // Add gradient definition for fade-out lines
    var defs = document.createElementNS(SVG_NS, "defs");
    svg.appendChild(defs);

    // Draw branch lines first (behind nodes)
    for (var i = 0; i < commits.length; i++) {
      var pLanes = layout.parentLanes[i];
      var myLane = layout.commitLanes[i];

      for (var p = 0; p < pLanes.length; p++) {
        var parentHash = pLanes[p].parentHash;
        var parentLane = pLanes[p].lane;
        var inWindow = pLanes[p].inWindow;

        var color = laneColor(myLane);

        if (!inWindow) {
          // Parent is outside the window — draw a short fade-out line
          var fx = laneX(myLane);
          var fy = rowY(i);
          var fadeLen = ROW_HEIGHT * 1.5;

          var gradId = "fade-" + i + "-" + p;
          var grad = document.createElementNS(SVG_NS, "linearGradient");
          grad.setAttribute("id", gradId);
          grad.setAttribute("x1", "0"); grad.setAttribute("y1", "0");
          grad.setAttribute("x2", "0"); grad.setAttribute("y2", "1");
          var stop1 = document.createElementNS(SVG_NS, "stop");
          stop1.setAttribute("offset", "0%");
          stop1.setAttribute("stop-color", color);
          stop1.setAttribute("stop-opacity", "1");
          var stop2 = document.createElementNS(SVG_NS, "stop");
          stop2.setAttribute("offset", "100%");
          stop2.setAttribute("stop-color", color);
          stop2.setAttribute("stop-opacity", "0");
          grad.appendChild(stop1);
          grad.appendChild(stop2);
          defs.appendChild(grad);

          var fadePath = document.createElementNS(SVG_NS, "path");
          fadePath.setAttribute("d", "M" + fx + "," + fy + " L" + fx + "," + (fy + fadeLen));
          fadePath.setAttribute("stroke", "url(#" + gradId + ")");
          svg.appendChild(fadePath);
          continue;
        }

        // Find parent row index and its actual lane position
        var parentIndex = hashToIndex[parentHash];
        if (parentIndex === undefined) continue;

        var actualParentLane = layout.commitLanes[parentIndex];
        var x1 = laneX(myLane);
        var y1 = rowY(i);
        var x2 = laneX(actualParentLane);
        var y2 = rowY(parentIndex);

        var path = document.createElementNS(SVG_NS, "path");
        color = laneColor(p === 0 ? myLane : actualParentLane);

        if (myLane === actualParentLane) {
          path.setAttribute("d", "M" + x1 + "," + y1 + " L" + x2 + "," + y2);
        } else {
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

  var MAX_REF_LABEL_LENGTH = 30;

  function shortenRefName(name) {
    if (name.length <= MAX_REF_LABEL_LENGTH) return name;
    // Try to shorten: keep first and last segments with ellipsis
    var parts = name.split("/");
    if (parts.length >= 3) {
      // e.g. "jack/oss-5-keyboard-shortcut-menu-bar-command-palette" → "jack/oss-5-keyboard-shor…"
      var prefix = parts[0] + "/";
      var rest = parts.slice(1).join("/");
      if (rest.length > MAX_REF_LABEL_LENGTH - prefix.length) {
        return prefix + rest.substring(0, MAX_REF_LABEL_LENGTH - prefix.length - 1) + "\u2026";
      }
      return prefix + rest;
    }
    return name.substring(0, MAX_REF_LABEL_LENGTH - 1) + "\u2026";
  }

  function createRefLabels(refs) {
    var frag = document.createDocumentFragment();
    if (!refs || refs.length === 0) return frag;

    for (var i = 0; i < refs.length; i++) {
      var ref = refs[i];
      var span = document.createElement("span");
      span.className = "ref-label";
      var displayName = shortenRefName(ref.name);
      span.textContent = displayName;
      if (displayName !== ref.name) {
        span.title = ref.name; // full name on hover
      }

      if (ref.type === "tag") {
        span.classList.add("ref-tag");
      } else {
        span.classList.add("ref-branch");
        if (ref.isHead) {
          span.classList.add("current");
        }
      }
      frag.appendChild(span);
    }
    return frag;
  }

  function formatRelativeDate(isoString) {
    if (!isoString) return "";
    var date = new Date(isoString);
    if (isNaN(date.getTime())) return isoString;
    var now = Date.now();
    var diffSec = Math.floor((now - date.getTime()) / 1000);
    if (diffSec < 60) return "just now";
    var diffMin = Math.floor(diffSec / 60);
    if (diffMin < 60) return diffMin + (diffMin === 1 ? " minute ago" : " minutes ago");
    var diffHr = Math.floor(diffMin / 60);
    if (diffHr < 24) return diffHr + (diffHr === 1 ? " hour ago" : " hours ago");
    var diffDay = Math.floor(diffHr / 24);
    if (diffDay < 30) return diffDay + (diffDay === 1 ? " day ago" : " days ago");
    var diffMonth = Math.floor(diffDay / 30);
    if (diffMonth < 12) return diffMonth + (diffMonth === 1 ? " month ago" : " months ago");
    var diffYear = Math.floor(diffDay / 365);
    return diffYear + (diffYear === 1 ? " year ago" : " years ago");
  }

  function createCommitRows(commits) {
    var frag = document.createDocumentFragment();

    for (var i = 0; i < commits.length; i++) {
      var commit = commits[i];
      var row = document.createElement("div");
      row.className = "commit-row";
      row.setAttribute("data-hash", commit.hash);

      // Left-click: open commit detail drawer
      row.addEventListener("click", (function (commitHash) {
        return function (e) {
          if (e.button !== 0) return;
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
      meta.textContent = commit.authorName + " \u00b7 " + formatRelativeDate(commit.authorDate);
      row.appendChild(meta);

      frag.appendChild(row);
    }

    return frag;
  }

  // -------------------------------------------------------
  // Main entry point
  // -------------------------------------------------------

  window.updateGraph = function (jsonString) {
    // Close drawer if open
    window.hideCommitDetail();

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

    // Build commitsByHash lookup
    commitsByHash = {};
    for (var ci2 = 0; ci2 < commits.length; ci2++) {
      commitsByHash[commits[ci2].hash] = commits[ci2];
    }

    // Map refs to their commits, deduplicating remote tracking branches
    var refsByHash = {};
    var localBranchNames = {};
    if (data.refs) {
      // First pass: collect local branch names
      for (var ri = 0; ri < data.refs.length; ri++) {
        if (data.refs[ri].type === "localBranch") {
          localBranchNames[data.refs[ri].name] = true;
        }
      }
      // Second pass: add refs, skipping remotes that duplicate a local branch
      for (var ri2 = 0; ri2 < data.refs.length; ri2++) {
        var ref = data.refs[ri2];
        if (ref.type === "remoteBranch") {
          // Strip "origin/" (or any remote prefix) to check for local duplicate
          var slashIdx = ref.name.indexOf("/");
          var shortName = slashIdx !== -1 ? ref.name.substring(slashIdx + 1) : ref.name;
          if (localBranchNames[shortName]) continue; // skip — local branch already shown
          if (shortName === "HEAD") continue; // skip origin/HEAD
        }
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

window.getScrollY = function () {
    return window.scrollY || document.documentElement.scrollTop || 0;
};

window.setScrollY = function (y) {
    window.scrollTo(0, y);
};
