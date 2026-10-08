import QtQuick
import QtQuick.Controls as QQC2
import QtTest

// Shared by the tests: finding things in the popup by what a screen reader
// would call them, and moving between its views.
TestCase {
    id: util

    // The QuickSettings item under test
    property Item popup

    function findAll(item, pred, out) {
        out = out || [];
        if (pred(item)) out.push(item);
        for (let i = 0; i < item.children.length; i++) findAll(item.children[i], pred, out);
        return out;
    }
    // Showing controls with this accessible name
    function named(name) {
        return findAll(popup, i => i.Accessible && !i.Accessible.ignored && i.Accessible.name === name && i.visible && i.width > 0 && i.height > 0);
    }
    function one(name) {
        const r = named(name);
        verify(r.length === 1, "one '" + name + "' showing, got " + r.length);
        return r[0];
    }
    function has(name) { return named(name).length > 0; }
    function stack() { return findAll(popup, i => i.hasOwnProperty("depth") && i.hasOwnProperty("currentItem"))[0]; }
    function goMain() {
        const st = stack();
        while (st.depth > 1) st.pop(null, QQC2.StackView.Immediate);
        wait(100);
    }
    // Press a chevron (or tile body) and wait until its view is in
    function open(name, depth) {
        const st = stack();
        const before = st.depth;
        mouseClick(one(name));
        tryVerify(() => st.depth === before + 1 && !st.busy, 3000, "view opened by " + name);
    }
    function back() {
        const st = stack();
        const before = st.depth;
        mouseClick(one("Back to Quick Settings"));
        tryVerify(() => st.depth === before - 1 && !st.busy, 3000, "back");
    }
    function typeText(t) { for (const ch of t) keyClick(ch); }
    function sliderOf(name) {
        const r = findAll(popup, i => i.hasOwnProperty("snapMode") && i.hasOwnProperty("handle") && i.Accessible.name === name && i.visible);
        verify(r.length === 1, "one slider '" + name + "', got " + r.length);
        return r[0];
    }
    // Click a slider at a fraction of its length
    function clickSlider(s, fraction) {
        mouseClick(s, s.leftPadding + s.availableWidth * fraction, s.height / 2);
    }
}
