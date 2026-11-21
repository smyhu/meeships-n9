.pragma library
// MeeShips rules and computer player. Board 10x10, cell index i = y*10 + x.
// Fleet (classic Polish rules): 1x four, 2x three, 3x two, 4x one cells. Ships never touch, not even at corners.
// MIT, Copyright (c) 2026 smyhu.

var N = 10;
var FLEET = [4, 3, 3, 2, 2, 2, 1, 1, 1, 1];

// ship = { x, y, len, h (true = horizontal) }
function cells(s) {
    var out = [];
    for (var k = 0; k < s.len; k++) out.push(s.h ? s.y * N + s.x + k : (s.y + k) * N + s.x);
    return out;
}

// can ship s stand next to the ships in list (skipping index skip)?
function canPlace(list, s, skip) {
    if (s.x < 0 || s.y < 0) return false;
    if (s.h ? s.x + s.len > N : s.y + s.len > N) return false;
    if (!s.h && s.x >= N) return false;
    if (s.h && s.y >= N) return false;
    var x0 = s.x - 1, y0 = s.y - 1;
    var x1 = s.h ? s.x + s.len : s.x + 1, y1 = s.h ? s.y + 1 : s.y + s.len;
    for (var i = 0; i < list.length; i++) {
        if (i === skip) continue;
        var o = list[i];
        var ox1 = o.h ? o.x + o.len - 1 : o.x, oy1 = o.h ? o.y : o.y + o.len - 1;
        if (o.x <= x1 && ox1 >= x0 && o.y <= y1 && oy1 >= y0) return false;
    }
    return true;
}

function randomFleet() {
    for (var tries = 0; tries < 200; tries++) {
        var list = [], ok = true;
        for (var f = 0; f < FLEET.length && ok; f++) {
            var placed = false;
            for (var t = 0; t < 300; t++) {
                var h = Math.random() < 0.5;
                var len = FLEET[f];
                var s = { x: Math.floor(Math.random() * (h ? N - len + 1 : N)),
                          y: Math.floor(Math.random() * (h ? N : N - len + 1)), len: len, h: h };
                if (canPlace(list, s, -1)) { list.push(s); placed = true; break; }
            }
            if (!placed) ok = false;
        }
        if (ok) return list;
    }
    return [];
}

// index of the ship covering cell i, or -1
function shipAt(list, i) {
    for (var k = 0; k < list.length; k++) {
        var c = cells(list[k]);
        for (var j = 0; j < c.length; j++) if (c[j] == i) return k;
    }
    return -1;
}

// cells around a ship (inside the board, not the ship itself)
function around(s) {
    var out = [], c = cells(s), x, y;
    var x0 = s.x - 1, y0 = s.y - 1, x1 = s.h ? s.x + s.len : s.x + 1, y1 = s.h ? s.y + 1 : s.y + s.len;
    for (y = y0; y <= y1; y++) for (x = x0; x <= x1; x++) {
        if (x < 0 || y < 0 || x >= N || y >= N) continue;
        var i = y * N + x;
        if (c.indexOf(i) < 0) out.push(i);
    }
    return out;
}

// ---------- a board under fire ----------
// marks[i]: 0 untouched, 1 miss, 2 hit, 3 auto-miss (water next to a sunk ship)
// result of a shot: 0 miss, 1 hit, 2 sunk, -1 already shot
function newSide(ships) {
    var m = [];
    for (var i = 0; i < N * N; i++) m.push(0);
    var hits = [];
    for (var k = 0; k < ships.length; k++) hits.push(0);
    return { ships: ships, marks: m, hits: hits, sunk: [], left: ships.length };
}

function fire(side, i) {
    if (side.marks[i] != 0) return { r: -1 };
    var k = shipAt(side.ships, i);
    if (k < 0) { side.marks[i] = 1; return { r: 0 }; }
    side.marks[i] = 2;
    side.hits[k]++;
    if (side.hits[k] < side.ships[k].len) return { r: 1 };
    side.sunk.push(k);
    side.left--;
    var ar = around(side.ships[k]);
    for (var j = 0; j < ar.length; j++) if (side.marks[ar[j]] == 0) side.marks[ar[j]] = 3;
    return { r: 2, ship: side.ships[k], over: side.left == 0 };
}

// view of the enemy board kept by the shooter (enemy ships unknown until sunk)
function newView() {
    var m = [];
    for (var i = 0; i < N * N; i++) m.push(0);
    return { marks: m, sunk: [], left: FLEET.length };
}

function applyResult(view, i, r, ship) {
    if (r == 0) { view.marks[i] = 1; return; }
    view.marks[i] = 2;
    if (r == 2 && ship) {
        view.sunk.push(ship);
        view.left--;
        var ar = around(ship);
        for (var j = 0; j < ar.length; j++) if (view.marks[ar[j]] == 0) view.marks[ar[j]] = 3;
    }
}

// lengths of enemy ships not sunk yet (from a view)
function remaining(view) {
    var left = FLEET.slice(0);
    for (var k = 0; k < view.sunk.length; k++) {
        var p = left.indexOf(view.sunk[k].len);
        if (p >= 0) left.splice(p, 1);
    }
    return left;
}

// ---------- computer player ----------
// level 0 easy: random shots, finishes a hit ship only sometimes
// level 1 normal: hunts on a checkerboard, finishes hit ships
// level 2 hard: counts every possible position of the remaining ships and fires at the likeliest cell
function aiShot(view, level) {
    var m = view.marks, i, hits = [];
    for (i = 0; i < N * N; i++) if (m[i] == 2 && !inSunk(view, i)) hits.push(i);
    var free = [];
    for (i = 0; i < N * N; i++) if (m[i] == 0) free.push(i);
    if (free.length == 0) return -1;
    if (level == 0) {
        if (hits.length > 0 && Math.random() < 0.3) {
            var nb = neighbours(view, hits);
            if (nb.length > 0) return nb[Math.floor(Math.random() * nb.length)];
        }
        return free[Math.floor(Math.random() * free.length)];
    }
    var heat = density(view, hits);
    if (level == 1 && hits.length == 0) {
        // checkerboard hunt with a little randomness
        var even = [];
        for (i = 0; i < free.length; i++) {
            var c = free[i];
            if (((c % N) + Math.floor(c / N)) % 2 == 0) even.push(c);
        }
        var pool = even.length > 0 ? even : free;
        return pool[Math.floor(Math.random() * pool.length)];
    }
    var best = -1, bestV = -1, ties = [];
    for (i = 0; i < N * N; i++) {
        if (m[i] != 0) continue;
        if (heat[i] > bestV) { bestV = heat[i]; ties = [i]; }
        else if (heat[i] == bestV) ties.push(i);
    }
    if (ties.length == 0) return free[0];
    best = ties[Math.floor(Math.random() * ties.length)];
    return best;
}

function inSunk(view, i) {
    for (var k = 0; k < view.sunk.length; k++) if (cells(view.sunk[k]).indexOf(i) >= 0) return true;
    return false;
}

function neighbours(view, hits) {
    var out = [];
    for (var k = 0; k < hits.length; k++) {
        var x = hits[k] % N, y = Math.floor(hits[k] / N);
        var d = [[1, 0], [-1, 0], [0, 1], [0, -1]];
        for (var j = 0; j < 4; j++) {
            var nx = x + d[j][0], ny = y + d[j][1];
            if (nx < 0 || ny < 0 || nx >= N || ny >= N) continue;
            var c = ny * N + nx;
            if (view.marks[c] == 0 && out.indexOf(c) < 0) out.push(c);
        }
    }
    return out;
}

// how many placements of the remaining ships cover each cell; placements through open hits weigh a lot more
function density(view, hits) {
    var heat = [], i, m = view.marks;
    for (i = 0; i < N * N; i++) heat.push(0);
    var lens = remaining(view);
    for (var l = 0; l < lens.length; l++) {
        var len = lens[l];
        for (var o = 0; o < 2; o++) {
            var h = o == 0;
            if (len == 1 && !h) continue;
            for (var y = 0; y < (h ? N : N - len + 1); y++) for (var x = 0; x < (h ? N - len + 1 : N); x++) {
                var ok = true, cover = 0, k, c;
                for (k = 0; k < len; k++) {
                    c = h ? y * N + x + k : (y + k) * N + x;
                    if (m[c] == 1 || m[c] == 3 || (m[c] == 2 && inSunk(view, c))) { ok = false; break; }
                    if (m[c] == 2) cover++;
                }
                if (!ok) continue;
                if (hits.length > 0 && cover == 0) continue;
                var w = hits.length > 0 ? 1 + cover * 20 : 1;
                for (k = 0; k < len; k++) {
                    c = h ? y * N + x + k : (y + k) * N + x;
                    if (m[c] == 0) heat[c] += w;
                }
            }
        }
    }
    return heat;
}
