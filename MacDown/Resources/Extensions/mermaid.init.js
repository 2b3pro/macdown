// init mermaid

(function () {

  // Tell MacDown (if it is listening) that diagrams are done, so it can
  // restore the scroll position against the final layout. Called once.
  var notified = false;
  var notify = function () {
    if (notified)
      return;
    notified = true;
    if (typeof MermaidListener !== "undefined")
      MermaidListener.invokeCallbackForKey_("End");
  };

  // Pick the Mermaid theme from the preview's actual background, since the
  // user's preview style (not the system appearance) decides light or dark.
  var isDarkBackground = function () {
    var elements = [document.body, document.documentElement];
    for (var i = 0; i < elements.length; i++) {
      if (!elements[i])
        continue;
      var color = window.getComputedStyle(elements[i]).backgroundColor;
      var m = color.match(/rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?/);
      if (!m || (m[4] !== undefined && parseFloat(m[4]) === 0))
        continue;
      var luminance = (0.299 * m[1] + 0.587 * m[2] + 0.114 * m[3]) / 255;
      return luminance < 0.5;
    }
    return false;
  };

  var init = function () {
    try {
      var codes = document.querySelectorAll("code.language-mermaid");
      if (typeof mermaid === "undefined" || codes.length === 0) {
        notify();
        return;
      }

      // Code blocks are rendered as <div><pre><code>; turn the wrapper div
      // into the element Mermaid replaces with the SVG.
      var nodes = [];
      for (var i = 0; i < codes.length; i++) {
        var code = codes[i];
        var source = code.textContent;
        var pre = code.parentElement;
        var target = pre;
        if (pre.tagName === "PRE" && pre.parentElement.tagName === "DIV")
          target = pre.parentElement;
        var node = document.createElement("div");
        node.className = "mermaid";
        node.textContent = source;
        target.parentNode.replaceChild(node, target);
        nodes.push(node);
      }

      mermaid.initialize({
        startOnLoad: false,
        theme: isDarkBackground() ? "dark" : "default"
      });

      // Never leave MacDown waiting on a diagram that hangs.
      setTimeout(notify, 10000);
      mermaid.run({ nodes: nodes, suppressErrors: true }).then(notify, notify);
    } catch (e) {
      console.error("Mermaid rendering failed:", e);
      notify();
    }
  };

  if (typeof window.addEventListener != "undefined") {
    window.addEventListener("load", init, false);
  } else {
    window.attachEvent("onload", init);
  }
})();
