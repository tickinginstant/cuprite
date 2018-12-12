class InvalidSelector extends Error {}

const EVENTS = {
  FOCUS: ["blur", "focus", "focusin", "focusout"],
  MOUSE: ["click", "dblclick", "mousedown", "mouseenter", "mouseleave",
          "mousemove", "mouseover", "mouseout", "mouseup", "contextmenu"],
  FORM: ["submit"]
}

class Node {
  constructor(native) {
    this.native = native;
  }

  tagName() {
    return this.native.tagName.toLowerCase();
  }

  clearValue() {
    this.native.value = '';
  }

  allText() {
    return this.native.textContent;
  }

  property(name) {
    return this.native[name];
  }

  isVisible() {
    let node = this.native;
    let mapName, style;
    // if node is area, check visibility of relevant image
    if (node.tagName === "AREA") {
      mapName = document.evaluate("./ancestor::map/@name", node, null, XPathResult.STRING_TYPE, null).stringValue;
      node = document.querySelector(`img[usemap="#${mapName}"]`);
      if (node == null) {
        return false;
      }
    }

    while (node) {
      style = window.getComputedStyle(node);
      if (style.display === "none" || style.visibility === "hidden" || parseFloat(style.opacity) === 0) {
        return false;
      }
      node = node.parentElement;
    }

    return true;
  }

  visibleText() {
    if (this.isVisible()) {
      if (this.native.nodeName == "TEXTAREA") {
        return this.native.textContent;
      } else {
        if (this.native instanceof SVGElement) {
          return this.native.textContent;
        } else {
          return this.native.innerText;
        }
      }
    }
  }

  isDisabled() {
    let xpath = "parent::optgroup[@disabled] | \
                 ancestor::select[@disabled] | \
                 parent::fieldset[@disabled] | \
                 ancestor::*[not(self::legend) or preceding-sibling::legend][parent::fieldset[@disabled]]";

    return this.native.disabled || document.evaluate(xpath, this.native, null, XPathResult.BOOLEAN_TYPE, null).booleanValue;
  }

  value() {
    if (this.native.tagName == "SELECT" && this.native.multiple) {
      let result = []

      for (let i = 0, len = this.native.children.length; i < len; i++) {
        let option = this.native.children[i];
        if (option.selected) {
          result.push(option.value);
        }
      }

      return result;
    } else {
      return this.native.value;
    }
  }

  getAttributes() {
    let attrs = {};

    for (let i = 0, len = this.native.attributes.length; i < len; i++) {
      let attr = this.native.attributes[i];
      attrs[attr.name] = attr.value.replace("\n", "\\n");
    }

    return attrs;
  }

  getAttribute(name) {
    if (name == "checked" || name == "selected") {
      return this.native[name];
    } else {
      return this.native.getAttribute(name);
    }
  }

  path() {
    let nodes = [this.native];
    let parent = this.native.parentNode;

    while (parent !== document) {
      nodes.unshift(parent);
      parent = parent.parentNode;
    }

    let selectors = nodes.map(n => {
      let prevSiblings = [];
      let xpath = document.evaluate(`./preceding-sibling::${n.tagName}`, n, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);

      for (let i = 0; i < xpath.snapshotLength; i++) {
        prevSiblings.push(xpath.snapshotItem(i));
      }

      return `${n.tagName}[${(prevSiblings.length + 1)}]`;
    });

    return `//${selectors.join("/")}`;
  }

  scrollIntoViewport() {
    this.native.scrollIntoViewIfNeeded();

    if (!this._isInViewport()) {
      this.native.scrollIntoView({block: "center", inline: "center", behavior: "instant"});
      return this._isInViewport();
    }

    return true;
  }

  select(value) {
    if (this.isDisabled()) {
      return false;
    } else if (value == false && !this.native.parentNode.multiple) {
      return false;
    } else {
      this.trigger("focus", {}, this.native.parentNode);

      this.native.selected = value;
      this._changed();

      this.trigger("blur", {}, this.native.parentNode)
      return true;
    }
  }

  _changed() {
    let element;
    let event = document.createEvent("HTMLEvents");
    event.initEvent("change", true, false);

    // In the case of an OPTION tag, the change event should come
    // from the parent SELECT
    if (this.native.nodeName == "OPTION") {
      element = this.native.parentNode
      if (element.nodeName == "OPTGROUP") {
        element = element.parentNode
      }
      element
    } else {
      element = this.native
    }

    element.dispatchEvent(event)
  }

  trigger(name, options = {}, element) {
    let event;

    if (EVENTS.MOUSE.indexOf(name) != -1) {
      event = document.createEvent("MouseEvent");
      event.initMouseEvent(
        name, true, true, window, 0,
        options["screenX"] || 0, options["screenY"] || 0,
        options["clientX"] || 0, options["clientY"] || 0,
        options["ctrlKey"] || false,
        options["altKey"] || false,
        options["shiftKey"] || false,
        options["metaKey"] || false,
        options["button"] || 0, null
      )
    } else if (EVENTS.FOCUS.indexOf(name) != -1) {
      event = this._obtainEvent(name);
    } else if (EVENTS.FORM.indexOf(name) != -1) {
      event = this._obtainEvent(name);
    } else {
      throw "Unknown event";
    }

    element.dispatchEvent(event);
  }

  _obtainEvent(name) {
    let event = document.createEvent("HTMLEvents");
    event.initEvent(name, true, true);
    return event;
  }

  _isInViewport() {
    let rect = this.native.getBoundingClientRect();
    return rect.top >= 0 &&
           rect.left >= 0 &&
           rect.bottom <= window.innerHeight &&
           rect.right <= window.innerWidth;
  }
}


class Cuprite {
  constructor() {
    this.nodes = [];
    this.elements = [];
  }

  find(method, selector, within = document) {
    try {
      let results = [];

      if (method == "xpath") {
        let xpath = document.evaluate(selector, within, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
        for (let i = 0; i < xpath.snapshotLength; i++) {
          results.push(xpath.snapshotItem(i));
        }
      } else {
        results = within.querySelectorAll(selector);
      }

      return results;
    } catch (error) {
      // DOMException.INVALID_EXPRESSION_ERR is undefined, using pure code
      if (error.code == DOMException.SYNTAX_ERR || error.code == 51) {
        throw new InvalidSelector;
      } else {
        throw error;
      }
    }
  }

  getNode(id) {
    let node = this.nodes[id];
    if (node === undefined) {
      node = new Node(this.elements[id]);
      this.nodes[id] = node;
      return node;
    } else {
      return node;
    }
  }

  addNode(element) {
    if (this.elements.indexOf(element) >= 0) {
      return this.elements.indexOf(element);
    } else {
      this.elements.push(element);
      return this.elements.length - 1;
    }
  }

  equal(id, otherId) {
    return this.getNode(id).native == this.getNode(otherId).native;
  }

  evaluate(fn, args) {
    this._prepareArgs(args);
    let result = fn(...args);
    return this.wrapResults(result);
  }

  evaluate_async(fn, args) {
   this._prepareArgs(args);
   return new Promise((__resolve, __reject) => {
     try {
       args[args.length] = r => __resolve(this.wrapResults(r));
       args.length = args.length + 1;
       fn(...args);
     } catch(error) {
       __reject(error);
     }
   });
  }

  wrapResults(result){
    if (!this._visitedObjects) { this._visitedObjects = []; }

    switch (false) {
      case !Array.from(this._visitedObjects).includes(result):
        return '(cyclic structure)';
      case !Array.isArray(result) && !(result instanceof NodeList):
        return Array.from(result).map((res) => this.wrapResults(res));
      case !result || (result.nodeType !== 1) || !result['tagName']:
        return {'cupriteNodeId': this.addNode(result)};
      case result !== null:
        return undefined;
      case typeof result !== 'object':
        this._visitedObjects.push(result);
        var obj = {};
        for (let key of Object.keys(result || {})) {
          const val = result[key];
          obj[key] = this.wrapResults(val);
        }
        this._visitedObjects.pop();
        return obj;
      default:
        return result;
    }
  }

  _prepareArgs(args) {
    for(let i = 0; i < args.length; i++) {
      let arg = args[i];
      if (typeof(arg) == 'object' && arg.cupriteNodeId !== undefined) {
        args[i] = this.getNode(arg.cupriteNodeId).native;
      }
    }
  }
}

window._cuprite = new Cuprite;
