import Foundation
import JavaScriptCore

/// A JavaScript exception surfaced from `ReaderJSHarness`.
struct ReaderJSError: Error, CustomStringConvertible {
    let description: String
}

/// An in-process JavaScriptCore context carrying a small stand-in DOM, for
/// exercising the reader's injected scripts without a web view.
///
/// The stand-in models only what those scripts touch: element/text trees,
/// `createTreeWalker`, `splitText`/`replaceChild`/`normalize`, simple
/// `tag.class` descendant selectors, ranges over text nodes, a `window` with
/// scroll metrics, and recorded (never scheduled) listeners and timers. Tests
/// fire events with `dispatch` and run the timer queue with `flushTimers`.
/// Fixture markup is read by a deliberately small parser: keep it well formed.
final class ReaderJSHarness {
    let context: JSContext

    init(body html: String = "") throws {
        guard let context = JSContext() else {
            throw ReaderJSError(description: "JSContext could not be created")
        }
        self.context = context
        try run(Self.domShim)
        if !html.isEmpty { try setBody(html) }
    }

    /// Evaluates `script`, turning a thrown JavaScript exception into a Swift error.
    @discardableResult
    func run(_ script: String) throws -> JSValue {
        context.exception = nil
        let result = context.evaluateScript(script)
        if let exception = context.exception {
            context.exception = nil
            throw ReaderJSError(description: "JavaScript exception: \(exception)")
        }
        guard let result else { throw ReaderJSError(description: "evaluateScript returned nil") }
        return result
    }

    /// Calls the global function `name` with Swift values bridged as real JS
    /// values, so no test has to splice strings into source.
    @discardableResult
    func call(_ name: String, _ arguments: [Any] = []) throws -> JSValue {
        context.exception = nil
        guard let function = context.objectForKeyedSubscript(name), !function.isUndefined else {
            throw ReaderJSError(description: "\(name) is not defined")
        }
        let result = function.call(withArguments: arguments)
        if let exception = context.exception {
            context.exception = nil
            throw ReaderJSError(description: "JavaScript exception: \(exception)")
        }
        guard let result else { throw ReaderJSError(description: "\(name) returned nil") }
        return result
    }

    /// Binds a Swift value to a JS global.
    func set(_ name: String, _ value: Any) {
        context.setObject(value, forKeyedSubscript: name as NSString)
    }

    /// Replaces `document.body`'s children with parsed `html`.
    func setBody(_ html: String) throws {
        set("__fixture", html)
        try run("document.body.innerHTML = __fixture;")
    }

    var bodyHTML: String {
        get throws { try run("document.body.innerHTML").toString() }
    }

    var bodyText: String {
        get throws { try run("document.body.textContent").toString() }
    }

    /// Runs queued timers (and intervals, until cleared) in delay order.
    @discardableResult
    func flushTimers() throws -> Int {
        Int(try run("__flushTimers()").toInt32())
    }

    /// Fires a recorded listener: `target` is `"document"` or `"window"`.
    func dispatch(_ type: String, on target: String = "document") throws {
        try run("__dispatch(\(target), '\(type)');")
    }

    /// Records `postMessage` bodies sent to `window.webkit.messageHandlers[name]`.
    func installMessageHandler(_ name: String) throws {
        try call("__installHandler", [name])
    }

    func messages(for handler: String) throws -> [Any] {
        try run("window.__messages['\(handler)'] || []").toArray() ?? []
    }

    /// Sets what `window.getSelection()` reports. A nil text is "no selection".
    func setSelection(_ text: String?, rect: CGRect = .zero) throws {
        if let text {
            try call("__setSelection", [text, Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)])
        } else {
            try run("window.__selection = { rangeCount: 0 };")
        }
    }

    // MARK: - DOM stand-in

    static let domShim = #"""
    var window = globalThis;
    var NodeFilter = { SHOW_ELEMENT: 1, SHOW_TEXT: 4, SHOW_ALL: 0xFFFFFFFF };

    function __siblingAt(node, delta) {
        var parent = node.parentNode;
        if (!parent) { return null; }
        var index = parent.childNodes.indexOf(node);
        return parent.childNodes[index + delta] || null;
    }

    function __defineNodeBasics(proto) {
        Object.defineProperty(proto, 'nextSibling', { get: function() { return __siblingAt(this, 1); } });
        Object.defineProperty(proto, 'previousSibling', { get: function() { return __siblingAt(this, -1); } });
        Object.defineProperty(proto, 'parentElement', {
            get: function() { return this.parentNode && this.parentNode.nodeType === 1 ? this.parentNode : null; }
        });
        proto.remove = function() { if (this.parentNode) { this.parentNode.removeChild(this); } };
    }

    function GroveText(text) {
        this.nodeType = 3;
        this.nodeName = '#text';
        this.data = String(text);
        this.parentNode = null;
    }
    __defineNodeBasics(GroveText.prototype);
    Object.defineProperty(GroveText.prototype, 'textContent', {
        get: function() { return this.data; },
        set: function(value) { this.data = String(value); }
    });
    Object.defineProperty(GroveText.prototype, 'length', { get: function() { return this.data.length; } });
    GroveText.prototype.splitText = function(offset) {
        if (offset < 0 || offset > this.data.length) { throw new Error('IndexSizeError'); }
        var tail = new GroveText(this.data.slice(offset));
        this.data = this.data.slice(0, offset);
        if (this.parentNode) { this.parentNode.insertBefore(tail, this.nextSibling); }
        return tail;
    };

    function GroveClassList(element) { this.element = element; }
    GroveClassList.prototype.values = function() {
        return (this.element.getAttribute('class') || '').split(/\s+/).filter(function(c) { return c; });
    };
    GroveClassList.prototype.contains = function(name) { return this.values().indexOf(name) !== -1; };
    GroveClassList.prototype.add = function(name) {
        var list = this.values();
        if (list.indexOf(name) === -1) { list.push(name); }
        this.element.setAttribute('class', list.join(' '));
    };
    GroveClassList.prototype.remove = function(name) {
        this.element.setAttribute('class', this.values().filter(function(c) { return c !== name; }).join(' '));
    };

    function GroveStyle() {}
    GroveStyle.prototype.setProperty = function(name, value) { this[name] = String(value); };
    GroveStyle.prototype.getPropertyValue = function(name) { return this[name] === undefined ? '' : this[name]; };

    function GroveElement(tag) {
        this.nodeType = 1;
        this.tagName = String(tag).toUpperCase();
        this.nodeName = this.tagName;
        this.childNodes = [];
        this.parentNode = null;
        this._attrs = [];
        this.style = new GroveStyle();
        this.classList = new GroveClassList(this);
    }
    __defineNodeBasics(GroveElement.prototype);
    GroveElement.prototype.getAttribute = function(name) {
        for (var i = 0; i < this._attrs.length; i++) {
            if (this._attrs[i][0] === name) { return this._attrs[i][1]; }
        }
        return null;
    };
    GroveElement.prototype.setAttribute = function(name, value) {
        for (var i = 0; i < this._attrs.length; i++) {
            if (this._attrs[i][0] === name) { this._attrs[i][1] = String(value); return; }
        }
        this._attrs.push([name, String(value)]);
    };
    GroveElement.prototype.removeAttribute = function(name) {
        this._attrs = this._attrs.filter(function(pair) { return pair[0] !== name; });
    };
    GroveElement.prototype.hasAttribute = function(name) { return this.getAttribute(name) !== null; };
    Object.defineProperty(GroveElement.prototype, 'className', {
        get: function() { return this.getAttribute('class') || ''; },
        set: function(value) { this.setAttribute('class', value); }
    });
    Object.defineProperty(GroveElement.prototype, 'id', {
        get: function() { return this.getAttribute('id') || ''; }
    });
    Object.defineProperty(GroveElement.prototype, 'firstChild', { get: function() { return this.childNodes[0] || null; } });
    Object.defineProperty(GroveElement.prototype, 'lastChild', {
        get: function() { return this.childNodes[this.childNodes.length - 1] || null; }
    });
    Object.defineProperty(GroveElement.prototype, 'children', {
        get: function() { return this.childNodes.filter(function(n) { return n.nodeType === 1; }); }
    });
    Object.defineProperty(GroveElement.prototype, 'textContent', {
        get: function() { return this.childNodes.map(function(n) { return n.textContent; }).join(''); },
        set: function(value) {
            this.childNodes.slice().forEach(function(n) { n.parentNode = null; });
            this.childNodes = [];
            if (String(value).length) { this.appendChild(new GroveText(value)); }
        }
    });
    Object.defineProperty(GroveElement.prototype, 'innerHTML', {
        get: function() { return this.childNodes.map(__serialize).join(''); },
        set: function(html) {
            this.childNodes.slice().forEach(function(n) { n.parentNode = null; });
            this.childNodes = [];
            var parsed = __parseFragment(String(html));
            for (var i = 0; i < parsed.length; i++) { this.appendChild(parsed[i]); }
        }
    });
    Object.defineProperty(GroveElement.prototype, 'outerHTML', { get: function() { return __serialize(this); } });
    GroveElement.prototype._detach = function(node) {
        if (node.parentNode) { node.parentNode.removeChild(node); }
    };
    GroveElement.prototype.appendChild = function(node) {
        this._detach(node);
        this.childNodes.push(node);
        node.parentNode = this;
        return node;
    };
    GroveElement.prototype.insertBefore = function(node, reference) {
        if (!reference) { return this.appendChild(node); }
        this._detach(node);
        var index = this.childNodes.indexOf(reference);
        if (index === -1) { throw new Error('NotFoundError'); }
        this.childNodes.splice(index, 0, node);
        node.parentNode = this;
        return node;
    };
    GroveElement.prototype.removeChild = function(node) {
        var index = this.childNodes.indexOf(node);
        if (index === -1) { throw new Error('NotFoundError'); }
        this.childNodes.splice(index, 1);
        node.parentNode = null;
        return node;
    };
    GroveElement.prototype.replaceChild = function(node, old) {
        if (this.childNodes.indexOf(old) === -1) { throw new Error('NotFoundError'); }
        this._detach(node);
        this.childNodes[this.childNodes.indexOf(old)] = node;
        node.parentNode = this;
        old.parentNode = null;
        return old;
    };
    GroveElement.prototype.normalize = function() {
        var merged = [];
        for (var i = 0; i < this.childNodes.length; i++) {
            var node = this.childNodes[i];
            if (node.nodeType === 3) {
                if (!node.data.length) { node.parentNode = null; continue; }
                var last = merged[merged.length - 1];
                if (last && last.nodeType === 3) { last.data += node.data; node.parentNode = null; continue; }
            } else {
                node.normalize();
            }
            merged.push(node);
        }
        this.childNodes = merged;
    };
    GroveElement.prototype.getBoundingClientRect = function() { return { top: 0, left: 0, width: 0, height: 0 }; };
    GroveElement.prototype.querySelectorAll = function(selector) { return __querySelect(this, selector); };
    GroveElement.prototype.querySelector = function(selector) { return __querySelect(this, selector)[0] || null; };
    GroveElement.prototype.getElementsByTagName = function(tag) { return __querySelect(this, tag); };

    // Selectors: comma-separated descendant chains of `tag`, `.class`, `#id`.
    function __compound(text) {
        var match = /^([A-Za-z][A-Za-z0-9]*|\*)?((?:[.#][-\w]+)*)$/.exec(text);
        if (!match) { throw new Error('Unsupported selector: ' + text); }
        var parts = match[2].match(/[.#][-\w]+/g) || [];
        return {
            tag: match[1] && match[1] !== '*' ? match[1].toUpperCase() : null,
            classes: parts.filter(function(p) { return p[0] === '.'; }).map(function(p) { return p.slice(1); }),
            ids: parts.filter(function(p) { return p[0] === '#'; }).map(function(p) { return p.slice(1); })
        };
    }
    function __matchesCompound(element, compound) {
        if (compound.tag && element.tagName !== compound.tag) { return false; }
        for (var i = 0; i < compound.classes.length; i++) {
            if (!element.classList.contains(compound.classes[i])) { return false; }
        }
        for (var j = 0; j < compound.ids.length; j++) {
            if (element.id !== compound.ids[j]) { return false; }
        }
        return true;
    }
    function __matchesChain(element, chain) {
        if (!__matchesCompound(element, chain[chain.length - 1])) { return false; }
        var index = chain.length - 2;
        for (var n = element.parentNode; n && index >= 0; n = n.parentNode) {
            if (n.nodeType === 1 && __matchesCompound(n, chain[index])) { index--; }
        }
        return index < 0;
    }
    function __querySelect(root, selector) {
        var groups = String(selector).split(',').map(function(group) {
            return group.trim().split(/\s+/).map(__compound);
        });
        var found = [];
        (function walk(node) {
            for (var i = 0; i < node.childNodes.length; i++) {
                var child = node.childNodes[i];
                if (child.nodeType !== 1) { continue; }
                for (var g = 0; g < groups.length; g++) {
                    if (__matchesChain(child, groups[g])) { found.push(child); break; }
                }
                walk(child);
            }
        })(root);
        return found;
    }

    // A small reader for well-formed fixtures: elements, attributes, text,
    // comments, the common void elements and raw-text SCRIPT/STYLE bodies.
    var __VOID = { area: 1, br: 1, col: 1, embed: 1, hr: 1, img: 1, input: 1, link: 1, meta: 1, source: 1, wbr: 1 };
    var __RAW = { script: 1, style: 1, noscript: 1 };
    function __decode(text) {
        return text.replace(/&(amp|lt|gt|quot|#39|nbsp);/g, function(_, name) {
            return { amp: '&', lt: '<', gt: '>', quot: '"', '#39': "'", nbsp: ' ' }[name];
        });
    }
    function __escapeText(text) {
        return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }
    function __parseFragment(html) {
        var root = new GroveElement('#fragment');
        var stack = [root];
        var i = 0;
        while (i < html.length) {
            var top = stack[stack.length - 1];
            if (html.startsWith('<!--', i)) {
                var endComment = html.indexOf('-->', i);
                i = endComment === -1 ? html.length : endComment + 3;
                continue;
            }
            if (html[i] === '<' && html[i + 1] === '/') {
                var close = html.indexOf('>', i);
                var closing = html.slice(i + 2, close).trim().toUpperCase();
                for (var s = stack.length - 1; s > 0; s--) {
                    if (stack[s].tagName === closing) { stack.length = s; break; }
                }
                i = close + 1;
                continue;
            }
            if (html[i] === '<' && /[A-Za-z]/.test(html[i + 1] || '')) {
                var tagRe = /<([A-Za-z][A-Za-z0-9-]*)((?:\s+[^\s=>\/]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?)*)\s*(\/?)>/y;
                tagRe.lastIndex = i;
                var m = tagRe.exec(html);
                if (m) {
                    var element = new GroveElement(m[1]);
                    var attrRe = /([^\s=>\/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
                    var a;
                    while ((a = attrRe.exec(m[2])) !== null) {
                        var value = a[2] !== undefined ? a[2] : (a[3] !== undefined ? a[3] : (a[4] !== undefined ? a[4] : ''));
                        element.setAttribute(a[1].toLowerCase(), __decode(value));
                    }
                    top.appendChild(element);
                    i = m.index + m[0].length;
                    var lower = m[1].toLowerCase();
                    if (__RAW[lower]) {
                        var endRaw = html.toLowerCase().indexOf('</' + lower, i);
                        if (endRaw === -1) { endRaw = html.length; }
                        if (endRaw > i) { element.appendChild(new GroveText(html.slice(i, endRaw))); }
                        var after = html.indexOf('>', endRaw);
                        i = after === -1 ? html.length : after + 1;
                    } else if (!__VOID[lower] && !m[3]) {
                        stack.push(element);
                    }
                    continue;
                }
            }
            var next = html.indexOf('<', i + 1);
            if (next === -1) { next = html.length; }
            top.appendChild(new GroveText(__decode(html.slice(i, next))));
            i = next;
        }
        var nodes = root.childNodes.slice();
        nodes.forEach(function(n) { n.parentNode = null; });
        return nodes;
    }
    function __serialize(node) {
        if (node.nodeType === 3) {
            var parent = node.parentNode;
            if (parent && __RAW[parent.tagName.toLowerCase()]) { return node.data; }
            return __escapeText(node.data);
        }
        var tag = node.tagName.toLowerCase();
        var attrs = node._attrs.map(function(pair) {
            return ' ' + pair[0] + '="' + pair[1].replace(/&/g, '&amp;').replace(/"/g, '&quot;') + '"';
        }).join('');
        if (__VOID[tag]) { return '<' + tag + attrs + '>'; }
        return '<' + tag + attrs + '>' + node.childNodes.map(__serialize).join('') + '</' + tag + '>';
    }

    // Listeners and timers are recorded, never scheduled.
    var __listeners = [];
    function __listenerAPI(target) {
        target.addEventListener = function(type, handler) {
            __listeners.push({ target: target, type: type, handler: handler });
        };
        target.removeEventListener = function(type, handler) {
            __listeners = __listeners.filter(function(l) {
                return !(l.target === target && l.type === type && l.handler === handler);
            });
        };
    }
    function __dispatch(target, type) {
        __listeners.filter(function(l) { return l.target === target && l.type === type; })
            .forEach(function(l) { l.handler({ type: type }); });
    }
    var __timers = [];
    var __cleared = {};
    var __nextTimer = 1;
    var __clock = 0;
    function __schedule(fn, delay, repeat, id) {
        var timerID = id || __nextTimer++;
        __timers.push({ id: timerID, fn: fn, at: __clock + (delay || 0), delay: delay || 0, repeat: repeat });
        return timerID;
    }
    function setTimeout(fn, delay) { return __schedule(fn, delay, false); }
    function setInterval(fn, delay) { return __schedule(fn, delay, true); }
    function clearTimeout(id) {
        __cleared[id] = true;
        __timers = __timers.filter(function(t) { return t.id !== id; });
    }
    function clearInterval(id) { clearTimeout(id); }
    function requestAnimationFrame(fn) { return setTimeout(fn, 16); }
    function __flushTimers() {
        var ran = 0;
        while (__timers.length && ran < 1000) {
            __timers.sort(function(a, b) { return a.at - b.at; });
            var timer = __timers.shift();
            __clock = timer.at;
            timer.fn();
            ran++;
            if (timer.repeat && !__cleared[timer.id]) {
                __schedule(timer.fn, timer.delay, true, timer.id);
            }
        }
        return ran;
    }

    var __html = new GroveElement('html');
    var __head = __html.appendChild(new GroveElement('head'));
    var __body = __html.appendChild(new GroveElement('body'));

    function GroveRange() { this.startContainer = null; this.startOffset = 0; this.endContainer = null; this.endOffset = 0; }
    GroveRange.prototype._check = function(node, offset) {
        var length = node.nodeType === 3 ? node.data.length : node.childNodes.length;
        if (offset < 0 || offset > length) { throw new Error('IndexSizeError'); }
    };
    GroveRange.prototype.setStart = function(node, offset) { this._check(node, offset); this.startContainer = node; this.startOffset = offset; };
    GroveRange.prototype.setEnd = function(node, offset) { this._check(node, offset); this.endContainer = node; this.endOffset = offset; };
    GroveRange.prototype.getBoundingClientRect = function() { return window.__rangeRect; };
    GroveRange.prototype.toString = function() {
        var texts = [];
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        while (walker.nextNode()) { texts.push(walker.currentNode); }
        var from = texts.indexOf(this.startContainer);
        var to = texts.indexOf(this.endContainer);
        if (from === -1 || to === -1) { return ''; }
        if (from === to) { return texts[from].data.slice(this.startOffset, this.endOffset); }
        var out = texts[from].data.slice(this.startOffset);
        for (var k = from + 1; k < to; k++) { out += texts[k].data; }
        return out + texts[to].data.slice(0, this.endOffset);
    };

    var document = {
        nodeType: 9,
        readyState: 'complete',
        documentElement: __html,
        head: __head,
        body: __body,
        createElement: function(tag) { return new GroveElement(tag); },
        createTextNode: function(text) { return new GroveText(text); },
        createRange: function() { window.__lastRange = new GroveRange(); return window.__lastRange; },
        createTreeWalker: function(root, whatToShow) {
            var show = whatToShow === undefined ? NodeFilter.SHOW_ALL : whatToShow;
            function accepts(node) {
                if (node.nodeType === 1) { return (show & NodeFilter.SHOW_ELEMENT) !== 0; }
                if (node.nodeType === 3) { return (show & NodeFilter.SHOW_TEXT) !== 0; }
                return false;
            }
            var walker = { root: root, currentNode: root };
            walker.nextNode = function() {
                var node = walker.currentNode;
                while (true) {
                    if (node.childNodes && node.childNodes.length) {
                        node = node.childNodes[0];
                    } else {
                        while (node !== root && !node.nextSibling) { node = node.parentNode; }
                        if (node === root) { return null; }
                        node = node.nextSibling;
                    }
                    if (accepts(node)) { walker.currentNode = node; return node; }
                }
            };
            return walker;
        },
        querySelectorAll: function(selector) { return __querySelect(__html, selector); },
        querySelector: function(selector) { return __querySelect(__html, selector)[0] || null; },
        getElementsByTagName: function(tag) { return __querySelect(__html, tag); }
    };
    __listenerAPI(document);
    __listenerAPI(window);

    window.scrollX = 0;
    window.scrollY = 0;
    window.innerWidth = 1024;
    window.innerHeight = 800;
    window.__rangeRect = { top: 400, left: 24, width: 120, height: 20 };
    window.__scrolls = [];
    window.scrollTo = function(a, b) {
        window.__scrolls.push(typeof a === 'object' ? a : { left: a, top: b });
    };
    window.__selection = { rangeCount: 0 };
    window.getSelection = function() { return window.__selection; };
    function __setSelection(text, x, y, width, height) {
        window.__selection = {
            rangeCount: 1,
            toString: function() { return text; },
            getRangeAt: function() {
                return { getBoundingClientRect: function() { return { left: x, top: y, width: width, height: height }; } };
            }
        };
    }
    window.__messages = {};
    window.webkit = { messageHandlers: {} };
    function __installHandler(name) {
        window.__messages[name] = [];
        window.webkit.messageHandlers[name] = {
            postMessage: function(body) { window.__messages[name].push(body); }
        };
    }
    """#
}
