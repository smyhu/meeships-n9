import QtQuick 1.1
import com.nokia.meego 1.0
import MeeGames 1.0
import "game.js" as G
import "state.js" as St
import "strings.js" as S

// MeeShips: the whole game lives on this one portrait page.
// Screens: menu, setup (place the fleet), play, wifi (find / invite a phone), stats, about.
Page {
    id: page
    orientationLock: PageOrientation.LockPortrait

    property string screen: "menu"
    property string mode: "ai"          // ai | net
    property int aiLevel: 1
    property bool series: false         // a hit gives another shot (option, off by default)
    property bool sound: true
    property string skin: "blocks"

    // setup
    property variant myShips: []        // [{x,y,len,h,f}] f = index in G.FLEET
    property int selected: 0            // fleet index being placed, -1 none
    property bool horiz: true
    property variant ghost: null
    property bool myReady: false
    property bool peerReady: false

    // battle
    property bool inGame: false
    property bool over: false
    property bool won: false
    property bool myTurn: false
    property bool busy: false
    property bool gameSeries: true
    property int shots: 0
    property string status: ""
    property string status2: ""
    property variant myMarks: []
    property variant mySunk: []
    property variant enemyMarks: []
    property variant enemySunk: []
    property variant enemyShown: []     // enemy ships shown at the end
    property variant enemyFleetSunk: [] // 10 bools in G.FLEET order
    property int aimEnemy: -1
    property int aimMine: -1
    property bool blink: true
    property bool askQuit: false        // in-game menu (hamburger) open
    property bool confirmQuit: false
    property bool peerAgain: false
    property bool askReset: false

    // wifi
    property variant peerList: []
    property string toast: ""
    property bool inviteIn: false
    property string inviteName: ""
    property variant stats: ({})

    property string lang: String(helper.language).substring(0, 2).toLowerCase()
    function tr(k) { return S.trl(k, page.lang) }

    Loader { id: sounds; source: "Sounds.qml" }
    FontLoader { id: arcade; source: "fonts/PressStart2P-Regular.ttf" }
    function sfx(name) { if (sound && sounds.item) sounds.item.play(name) }

    // ---------- settings and scores ----------
    function loadAll() {
        aiLevel = parseInt(helper.setting("aiLevel", 1), 10)
        if (!(aiLevel >= 0 && aiLevel <= 2)) aiLevel = 1
        series = String(helper.setting("series", false)) == "true"
        sound = String(helper.setting("sound", true)) == "true"
        loadStats()
    }
    function statKeys() { return ["ai0", "ai1", "ai2", "net"] }
    function loadStats() {
        var o = {}, k = statKeys()
        for (var i = 0; i < k.length; i++)
            o[k[i]] = { w: parseInt(helper.setting("w_" + k[i], 0), 10) || 0,
                        l: parseInt(helper.setting("l_" + k[i], 0), 10) || 0,
                        b: parseInt(helper.setting("b_" + k[i], 0), 10) || 0 }
        stats = o
    }
    function record(win) {
        var k = mode == "net" ? "net" : "ai" + aiLevel
        if (win) {
            helper.setSetting("w_" + k, (parseInt(helper.setting("w_" + k, 0), 10) || 0) + 1)
            var b = parseInt(helper.setting("b_" + k, 0), 10) || 0
            if (b == 0 || shots < b) helper.setSetting("b_" + k, shots)
        } else {
            helper.setSetting("l_" + k, (parseInt(helper.setting("l_" + k, 0), 10) || 0) + 1)
        }
        loadStats()
    }
    function resetStats() {
        var k = statKeys()
        for (var i = 0; i < k.length; i++) {
            helper.setSetting("w_" + k[i], 0); helper.setSetting("l_" + k[i], 0); helper.setSetting("b_" + k[i], 0)
        }
        loadStats()
    }

    // ---------- setup ----------
    function placedCount() { return myShips.length }
    function isPlaced(f) {
        for (var i = 0; i < myShips.length; i++) if (myShips[i].f == f) return true
        return false
    }
    function nextFree() {
        for (var f = 0; f < G.FLEET.length; f++) if (!isPlaced(f)) return f
        return -1
    }
    function startSetup() {
        myShips = []; selected = 0; horiz = true; ghost = null; myReady = false
        screen = "setup"
    }
    function tapSetup(i) {
        if (myReady) return
        var k = G.shipAt(myShips, i), list = [], j
        if (k >= 0) {
            // pick the ship up
            for (j = 0; j < myShips.length; j++) if (j != k) list.push(myShips[j])
            selected = myShips[k].f; horiz = myShips[k].h
            myShips = list
            sfx("move2")
            return
        }
        if (selected < 0) return
        var len = G.FLEET[selected]
        var s = { x: i % 10, y: Math.floor(i / 10), len: len, h: horiz, f: selected }
        if (horiz && s.x + len > 10) s.x = 10 - len
        if (!horiz && s.y + len > 10) s.y = 10 - len
        if (!G.canPlace(myShips, s, -1)) {
            ghost = s; ghostTimer.restart(); sfx("crash")
            return
        }
        for (j = 0; j < myShips.length; j++) list.push(myShips[j])
        list.push(s)
        myShips = list
        selected = nextFree()
        sfx("move1")
    }
    function randomSetup() {
        var r = G.randomFleet(), list = []
        for (var i = 0; i < r.length; i++) { var s = r[i]; s.f = i; list.push(s) }
        myShips = list; selected = -1; sfx("move2")
    }
    Timer { id: ghostTimer; interval: 450; onTriggered: page.ghost = null }

    function setupReady() {
        if (myShips.length != G.FLEET.length) return
        if (mode == "ai") { beginBattle(Math.random() < 0.5, series); return }
        myReady = true
        net.send(JSON.stringify({ t: "ready" }))
        maybeStartNet()
    }
    function maybeStartNet() {
        // the phone that sent the invitation decides who starts and which rules apply
        if (mode != "net" || !net.initiator || !myReady || !peerReady) return
        var first = Math.random() < 0.5
        net.send(JSON.stringify({ t: "start", first: first ? "me" : "you", series: series }))
        beginBattle(first, series)
    }

    // ---------- battle ----------
    function plainShips(list) {
        var out = []
        for (var i = 0; i < list.length; i++) out.push({ x: list[i].x, y: list[i].y, len: list[i].len, h: list[i].h })
        return out
    }
    function beginBattle(iStart, ser) {
        St.me = G.newSide(plainShips(myShips))
        St.view = G.newView()
        if (mode == "ai") { St.aiSide = G.newSide(G.randomFleet()); St.aiView = G.newView() }
        gameSeries = ser
        shots = 0; over = false; won = false; busy = false; askQuit = false; peerAgain = false
        peerReady = false; myReady = false
        aimEnemy = -1; aimMine = -1; enemyShown = []
        refresh()
        inGame = true
        screen = "play"
        myTurn = iStart
        status = iStart ? tr("youStart") : (mode == "ai" ? tr("aiTurn") : tr("peerTurn"))
        status2 = ""
        sfx("start")
        helper.keepScreenOn(true)
        if (!iStart && mode == "ai") aiTimer.restart()
    }
    function refresh() {
        myMarks = St.me.marks.slice(0)
        var ms = []
        for (var i = 0; i < St.me.sunk.length; i++) ms.push(St.me.ships[St.me.sunk[i]])
        mySunk = ms
        enemyMarks = St.view.marks.slice(0)
        enemySunk = St.view.sunk.slice(0)
        // which fleet entries are sunk
        var fs = [], used = [], k, j
        for (k = 0; k < G.FLEET.length; k++) fs.push(false)
        for (j = 0; j < St.view.sunk.length; j++)
            for (k = 0; k < G.FLEET.length; k++)
                if (!fs[k] && G.FLEET[k] == St.view.sunk[j].len) { fs[k] = true; break }
        enemyFleetSunk = fs
    }
    function resultText(r) { return r == 0 ? tr("miss") : (r == 1 ? tr("hit") : tr("sunk")) }

    // my shot
    function tapEnemy(i) {
        if (screen != "play" || over || !myTurn || busy || askQuit) return
        if (mode == "net" && net.reconnecting) return
        if (St.view.marks[i] != 0) return
        busy = true
        aimEnemy = i
        if (mode == "ai") { sfx("shot"); shotTimer.restart() }
        else {
            // Wi-Fi: the shot sounds only when the other phone has answered (automatically)
            net.send(JSON.stringify({ t: "shot", i: i }))
            waitTimer.restart()
        }
    }
    Timer { id: waitTimer; interval: 1500; onTriggered: if (page.busy) page.status2 = page.tr("waitShot") }
    property variant pendRes: null
    Timer {
        id: netResTimer; interval: 150
        onTriggered: { var m = page.pendRes; page.myResult(m.i, m.r, m.ship, m.over === true) }
    }
    Timer {
        id: shotTimer; interval: 380
        onTriggered: {
            var i = page.aimEnemy
            var res = G.fire(St.aiSide, i)
            page.myResult(i, res.r, res.ship, res.over)
        }
    }
    function myResult(i, r, ship, isOver) {
        G.applyResult(St.view, i, r, ship)
        shots++
        aimEnemy = -1
        refresh()
        status2 = resultText(r)
        sfx(r == 0 ? "splash" : (r == 1 ? "hit" : "sunk"))
        busy = false
        if (isOver) {
            if (mode == "net") net.send(JSON.stringify({ t: "reveal", ships: plainShips(myShips) }))
            finish(true)
            return
        }
        if (r == 0 || !gameSeries) {
            myTurn = false
            status = mode == "ai" ? tr("aiTurn") : tr("peerTurn")
            if (mode == "ai") aiTimer.restart()
        } else {
            status = tr("again")
        }
    }

    // enemy shot (computer or the other phone)
    Timer {
        id: aiTimer; interval: 750
        onTriggered: {
            if (page.over || !page.inGame) return
            if (page.askQuit || page.screen != "play") { aiTimer.restart(); return }   // wait while a menu is open
            var i = G.aiShot(St.aiView, page.aiLevel)
            page.aimMine = i
            aiFire.restart()
        }
    }
    Timer {
        id: aiFire; interval: 350
        onTriggered: {
            var i = page.aimMine
            var res = G.fire(St.me, i)
            G.applyResult(St.aiView, i, res.r, res.ship)
            page.incoming(i, res.r, res.over)
        }
    }
    function incoming(i, r, isOver) {
        aimMine = i
        aimMineOff.restart()
        refresh()
        status2 = resultText(r)
        sfx(r == 0 ? "splash" : (r == 1 ? "hit" : "sunk"))
        if (isOver) {
            if (mode == "ai") enemyShown = afloat(St.aiSide)
            finish(false)
            return
        }
        if (r > 0 && gameSeries) {
            status = mode == "ai" ? tr("aiAgain") : tr("peerAgain2")
            if (mode == "ai") aiTimer.restart()
        } else {
            myTurn = true
            status = tr("yourTurn")
        }
    }
    Timer { id: aimMineOff; interval: 900; onTriggered: page.aimMine = -1 }
    function afloat(side) {
        var out = []
        for (var k = 0; k < side.ships.length; k++) if (side.sunk.indexOf(k) < 0) out.push(side.ships[k])
        return out
    }
    function finish(win) {
        over = true; won = win; myTurn = false; inGame = false
        status = win ? tr("win") : tr("lose")
        record(win)
        sfx(win ? "record" : "gameover")
        helper.keepScreenOn(false)
    }
    function quitGame() {
        aiTimer.stop(); aiFire.stop(); shotTimer.stop()
        inGame = false; over = false; askQuit = false
        helper.keepScreenOn(false)
        if (mode == "net") { net.leave(); screen = "wifi" }
        else screen = "menu"
    }

    // ---------- network ----------
    GameNet {
        id: net
        gameId: "meeships"
        onPeersChanged: { var l = []; try { l = JSON.parse(net.peers) } catch (e) { l = [] } page.peerList = l }
        onLocalAddressChanged: page.fixName()
        onInvited: { page.inviteName = name + "  " + ip; page.inviteIn = true; page.sfx("bonus") }
        onInviteCancelled: { page.inviteIn = false; page.showToast(page.tr("cancelled")) }
        onAccepted: page.netStart()
        onDeclined: {
            page.showToast(reason == "busy" ? page.tr("rBusy") : (reason == "version" || reason == "game") ? page.tr("rVersion")
                         : (reason == "no" ? page.tr("rNo") : page.tr("rUnreach")))
            page.sfx("crash")
        }
        onMessage: page.netMessage(text)
        onLinkLost: { page.lostAt = new Date().getTime(); page.lostLeft = net.resumeSeconds; page.sfx("crash") }
        onResumed: { page.showToast(page.tr("linkBack")); page.sfx("bonus") }
        onPeerLeft: {
            var wasPlaying = page.screen == "play" || page.screen == "setup"
            aiTimer.stop()
            page.inGame = false; page.askQuit = false
            if (page.mode == "net" && (wasPlaying || page.over)) {
                page.over = false
                page.screen = "wifi"
                page.showToast(reason == "bye" ? page.tr("peerLeft") : page.tr("peerLost"))
                page.sfx("crash")
                helper.keepScreenOn(false)
            }
        }
    }
    function fixName() {
        var n = String(helper.setting("name", ""))
        if (n == "" || n == "undefined") {
            var a = String(net.localAddress)
            n = a != "" ? "N9-" + a.substring(a.lastIndexOf(".") + 1) : "N9"
        }
        net.name = n
    }
    function openWifi() {
        mode = "net"
        fixName()
        net.start()
        screen = "wifi"
    }
    function closeWifi() {
        net.stop()
        inviteIn = false
        mode = "ai"
        screen = "menu"
    }
    function acceptInvite() { inviteIn = false; net.accept(); netStart() }
    function netStart() {
        mode = "net"; peerReady = false; peerAgain = false
        sfx("bonus")
        startSetup()
    }
    function netMessage(text) {
        var m
        try { m = JSON.parse(text) } catch (e) { return }
        if (m.t == "ready") { peerReady = true; maybeStartNet() }
        else if (m.t == "start") beginBattle(m.first == "you", m.series === true)
        else if (m.t == "shot") {
            if (!St.me || over) return
            var res = G.fire(St.me, m.i)
            // a square shot before (or water next to a sunk ship): answer like before, never stall
            if (res.r < 0) res = { r: St.me.marks[m.i] == 2 ? 1 : 0 }
            net.send(JSON.stringify({ t: "res", i: m.i, r: res.r, ship: res.ship ? { x: res.ship.x, y: res.ship.y, len: res.ship.len, h: res.ship.h } : null, over: res.over === true }))
            incoming(m.i, res.r, res.over === true)
        }
        else if (m.t == "res") {
            if (!busy || m.i != aimEnemy || netResTimer.running) return
            waitTimer.stop()
            pendRes = m
            sfx("shot")
            netResTimer.restart()
        }
        else if (m.t == "reveal") {
            var shown = [], k
            for (k = 0; k < m.ships.length; k++) {
                var s = m.ships[k], c = G.cells(s), hit = false
                for (var j = 0; j < c.length; j++) if (St.view.marks[c[j]] == 2) hit = true
                var sunkAlready = false
                for (j = 0; j < St.view.sunk.length; j++)
                    if (St.view.sunk[j].x == s.x && St.view.sunk[j].y == s.y && St.view.sunk[j].h == s.h && St.view.sunk[j].len == s.len) sunkAlready = true
                if (!sunkAlready) shown.push(s)
            }
            enemyShown = shown
        }
        else if (m.t == "again") peerAgain = true
    }
    function rematch() {
        net.send(JSON.stringify({ t: "again" }))
        peerAgain = false
        over = false
        startSetup()
    }

    property double lostAt: 0
    property int lostLeft: 0
    property bool netDown: page.mode == "net" && net.reconnecting && (page.screen == "play" || page.screen == "setup")
    Timer {
        interval: 1000; repeat: true; running: page.netDown
        onTriggered: page.lostLeft = Math.max(0, net.resumeSeconds - Math.floor((new Date().getTime() - page.lostAt) / 1000))
    }
    property bool toastOn: false
    function showToast(t) { toast = t; toastOn = true; toastTimer.restart() }
    Timer { id: toastTimer; interval: 3500; onTriggered: page.toastOn = false }
    Timer { interval: 300; repeat: true; running: page.aimEnemy >= 0 || page.aimMine >= 0 || page.screen == "wifi" || page.netDown; onTriggered: page.blink = !page.blink }

    Component.onCompleted: loadAll()

    // ================= BACKGROUND =================
    Image { anchors.fill: parent; source: "background.png"; fillMode: Image.Stretch }

    // ================= MENU =================
    Item {
        anchors.fill: parent
        visible: page.screen == "menu"
        PixelText { anchors.horizontalCenter: parent.horizontalCenter; y: 60; text: tr("title"); pixelSize: 6 }
        // logo strip: the fleet as raw blocks
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 132; spacing: 14
            Repeater {
                model: [4, 3, 2, 1]
                Row {
                    property int n: modelData
                    spacing: 3
                    Repeater { model: parent.n; Rectangle { width: 16; height: 16; color: index == 1 && parent.n == 3 ? "#ff7a6a" : "#E7FFCD" } }
                }
            }
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 190; spacing: 14
            PixelButton { text: tr("resume"); visible: page.inGame && page.mode == "ai"; onClicked: page.screen = "play" }
            PixelButton { text: tr("newGame"); onClicked: { page.mode = "ai"; page.startSetup() } }
            PixelButton { text: tr("wifi"); onClicked: page.openWifi() }
            Rectangle {
                width: 400; height: 56; color: "#0c120a"; border.width: 4; border.color: "#E7FFCD"
                PixelText { anchors.centerIn: parent; text: tr("ai") + " " + tr("lv" + page.aiLevel); pixelSize: 4 }
                Rectangle {
                    width: 64; height: parent.height; color: lessArea.pressed ? "#E7FFCD" : "transparent"
                    PixelText { anchors.centerIn: parent; text: "<"; pixelSize: 4; color: lessArea.pressed ? "#0c120a" : "#E7FFCD" }
                    MouseArea { id: lessArea; anchors.fill: parent
                        onClicked: { page.aiLevel = (page.aiLevel + 2) % 3; helper.setSetting("aiLevel", page.aiLevel) } }
                }
                Rectangle {
                    anchors.right: parent.right
                    width: 64; height: parent.height; color: moreArea.pressed ? "#E7FFCD" : "transparent"
                    PixelText { anchors.centerIn: parent; text: ">"; pixelSize: 4; color: moreArea.pressed ? "#0c120a" : "#E7FFCD" }
                    MouseArea { id: moreArea; anchors.fill: parent
                        onClicked: { page.aiLevel = (page.aiLevel + 1) % 3; helper.setSetting("aiLevel", page.aiLevel) } }
                }
            }
            PixelButton {
                text: tr("series") + " " + (page.series ? tr("on") : tr("off"))
                onClicked: { page.series = !page.series; helper.setSetting("series", page.series); page.sfx("move1") }
            }
            PixelButton {
                text: tr("sound") + " " + (page.sound ? tr("on") : tr("off"))
                onClicked: { page.sound = !page.sound; helper.setSetting("sound", page.sound); page.sfx("eat") }
            }
            Row {
                spacing: 10
                PixelButton { width: 195; text: tr("stats"); onClicked: { page.askReset = false; page.screen = "stats" } }
                PixelButton { width: 195; text: tr("about"); onClicked: page.screen = "about" }
            }
        }
    }

    // ================= SETUP =================
    Item {
        anchors.fill: parent
        visible: page.screen == "setup"
        PixelText { anchors.horizontalCenter: parent.horizontalCenter; y: 22; text: tr("place"); pixelSize: 4 }
        Board {
            id: setupBoard
            x: 36; y: 64
            pitch: 40
            marks: []
            ships: page.myShips
            ghost: page.ghost
            skin: page.skin
            onTapped: page.tapSetup(i)
        }
        // ships still to place (tap to choose)
        Column {
            x: 36; y: 488; spacing: 10
            visible: !page.myReady
            Repeater {
                model: [[0], [1, 2], [3, 4, 5], [6, 7, 8, 9]]
                Row {
                    spacing: 14
                    Repeater {
                        model: modelData
                        Item {
                            property int f: modelData
                            property bool done: page.isPlaced(f) && page.myShips.length >= 0
                            width: G.FLEET[f] * 18 + 6; height: 22
                            Rectangle { anchors.fill: parent; color: "transparent"; border.width: 2; border.color: page.selected == parent.f ? "#f0d860" : "transparent" }
                            Row {
                                x: 4; y: 4; spacing: 2
                                Repeater { model: G.FLEET[f]; Rectangle { width: 16; height: 14; color: page.selected == f ? "#f0d860" : "#E7FFCD"; opacity: done ? 0.15 : 1 } }
                            }
                            MouseArea { anchors.fill: parent; anchors.margins: -6; enabled: !done; onClicked: { page.selected = parent.f; page.sfx("move1") } }
                        }
                    }
                }
            }
        }
        // chosen ship in its current direction
        Rectangle {
            x: 354; y: 488; width: 90; height: 90
            visible: !page.myReady
            color: "#0c120a"; border.width: 2; border.color: "#5f7f45"
            ShipBlock {
                property int ln: page.selected >= 0 ? G.FLEET[page.selected] : 0
                s: page.selected >= 0 ? ({ x: 0, y: 0, len: ln, h: page.horiz }) : null
                visible: page.selected >= 0
                pitch: 20; gap: 2; color: "#f0d860"
                anchors.centerIn: parent
            }
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 492; spacing: 14
            visible: page.myReady
            PixelText { anchors.horizontalCenter: parent.horizontalCenter; text: tr("waitPeer"); pixelSize: 3; color: page.blink ? "#E7FFCD" : "#cfeca0" }
        }
        PixelText {
            anchors.horizontalCenter: parent.horizontalCenter; y: 560
            visible: page.mode == "net" && page.peerReady
            text: tr("peerReady"); pixelSize: 2; color: "#cfeca0"
        }
        Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 610; columns: 2; spacing: 10
            PixelButton { width: 195; text: tr("rotate"); enabled: !page.myReady; onClicked: { page.horiz = !page.horiz; page.sfx("move2") } }
            PixelButton { width: 195; text: tr("random"); enabled: !page.myReady; onClicked: page.randomSetup() }
            PixelButton { width: 195; text: tr("clear"); enabled: !page.myReady && page.myShips.length > 0
                onClicked: { page.myShips = []; page.selected = 0; page.sfx("move2") } }
            PixelButton { width: 195; text: tr("ready"); enabled: !page.myReady && page.myShips.length == 10; onClicked: page.setupReady() }
        }
        PixelButton {
            anchors.horizontalCenter: parent.horizontalCenter; y: 770; width: 400
            text: page.mode == "net" ? tr("disconnect") : tr("back")
            onClicked: { if (page.mode == "net") { net.leave(); page.screen = "wifi" } else page.screen = "menu" }
        }
    }

    // ================= PLAY =================
    Item {
        anchors.fill: parent
        visible: page.screen == "play"

        PixelText { x: 16; y: 14; text: page.status; pixelSize: 3; color: page.over ? (page.won ? "#f0d860" : "#ff7a6a") : (page.myTurn ? "#E7FFCD" : "#cfeca0") }
        PixelText { x: 16; y: 48; text: page.status2; pixelSize: 2; color: "#9cc575" }
        Rectangle {
            id: menuBtn
            x: 480 - 10 - 52; y: 8; width: 52; height: 52
            color: menuArea.pressed ? "#E7FFCD" : "#0c120a"
            border.width: 2; border.color: "#5f7f45"
            Column {
                anchors.centerIn: parent; spacing: 5
                Repeater { model: 3; Rectangle { width: 24; height: 5; color: menuArea.pressed ? "#0c120a" : "#E7FFCD" } }
            }
            MouseArea { id: menuArea; anchors.fill: parent; anchors.margins: -8
                onClicked: {
                    if (page.over) { if (page.mode == "net") page.quitGame(); else page.screen = "menu"; return }
                    page.confirmQuit = false; page.askQuit = true
                } }
        }

        // enemy sea with coordinates
        Row {
            x: 62; y: 82
            Repeater { model: 10; Item { width: 39; height: 14
                PixelText { anchors.horizontalCenter: parent.horizontalCenter; text: "ABCDEFGHIJ".charAt(index); pixelSize: 2; color: "#9cc575" } } }
        }
        Column {
            x: 8; y: 104
            Repeater { model: 10; Item { width: 46; height: 39
                PixelText { anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: String(index + 1); pixelSize: 2; color: "#9cc575" } } }
        }
        Board {
            id: enemyBoard
            x: 58; y: 100
            pitch: 39
            marks: page.enemyMarks
            sunk: page.enemySunk
            ships: page.enemyShown
            aim: page.aimEnemy
            aimOn: page.blink
            skin: page.skin
            onTapped: page.tapEnemy(i)
        }

        // my fleet
        PixelText { x: 58; y: 522; text: tr("yourFleet"); pixelSize: 2; color: "#cfeca0" }
        Board {
            x: 58; y: 544
            pitch: 24; gap: 2; pad: 3
            marks: page.myMarks
            ships: page.screen == "play" ? page.myShips : []
            sunk: page.mySunk
            aim: page.aimMine
            aimOn: page.blink
            active: false
            skin: page.skin
        }

        // enemy fleet status + shots
        Column {
            x: 322; y: 522; spacing: 10
            PixelText { text: page.mode == "net" ? String(net.peerName).toUpperCase().substring(0, 12) : tr("computer") + "\n" + tr("lv" + page.aiLevel); pixelSize: 2; color: "#cfeca0" }
            Repeater {
                model: [[0], [1, 2], [3, 4, 5], [6, 7, 8, 9]]
                Row {
                    spacing: 8
                    Repeater {
                        model: modelData
                        Row {
                            property bool down: page.enemyFleetSunk.length == 10 && page.enemyFleetSunk[modelData]
                            spacing: 2
                            Repeater { model: G.FLEET[modelData]; Rectangle { width: 12; height: 12; color: parent.down ? "#ff7a6a" : "#E7FFCD"; opacity: parent.down ? 0.6 : 1 } }
                        }
                    }
                }
            }
            Item { width: 1; height: 12 }
            PixelText { text: tr("shots"); pixelSize: 2; color: "#cfeca0" }
            Text { text: String(page.shots); font.family: arcade.name; font.pixelSize: 24; color: "#E7FFCD" }
        }

        // end of the game
        Rectangle {
            visible: page.over
            x: 20; y: 520; width: 440; height: 320
            color: "#0c120a"; border.width: 2; border.color: page.won ? "#f0d860" : "#ff7a6a"
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 22; spacing: 14
                PixelText { anchors.horizontalCenter: parent.horizontalCenter; text: page.won ? tr("win") : tr("lose"); pixelSize: 5; color: page.won ? "#f0d860" : "#ff7a6a" }
                PixelText { anchors.horizontalCenter: parent.horizontalCenter; text: tr("shotsWin").replace("%1", page.shots); pixelSize: 2; color: "#cfeca0" }
                PixelText { anchors.horizontalCenter: parent.horizontalCenter; visible: page.mode == "net" && page.peerAgain; text: tr("peerAgain"); pixelSize: 2; color: page.blink ? "#f0d860" : "#E7FFCD" }
                PixelButton { width: 320; text: page.mode == "net" ? tr("rematch") : tr("newGame")
                    onClicked: { if (page.mode == "net") page.rematch(); else page.startSetup() } }
                PixelButton { width: 320; text: page.mode == "net" ? tr("disconnect") : tr("menu")
                    onClicked: { if (page.mode == "net") page.quitGame(); else { page.over = false; page.screen = "menu" } } }
            }
        }

        // in-game menu: back to the game, sound, main menu (solo), end game
        Rectangle {
            anchors.fill: parent
            visible: page.askQuit
            color: "#99000000"
            MouseArea { anchors.fill: parent; onClicked: { page.askQuit = false; page.confirmQuit = false } }
        }
        Rectangle {
            visible: page.askQuit && !page.confirmQuit
            x: 30; y: 200; width: 420; height: page.mode == "ai" ? 410 : 340
            color: "#0c120a"; border.width: 2; border.color: "#E7FFCD"
            MouseArea { anchors.fill: parent }
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 26; spacing: 14
                PixelText { anchors.horizontalCenter: parent.horizontalCenter; text: tr("menu"); pixelSize: 4 }
                PixelButton { width: 360; text: tr("resume"); onClicked: page.askQuit = false }
                PixelButton { width: 360; text: tr("sound") + " " + (page.sound ? tr("on") : tr("off"))
                    onClicked: { page.sound = !page.sound; helper.setSetting("sound", page.sound); page.sfx("eat") } }
                PixelButton { width: 360; visible: page.mode == "ai"; text: tr("mainMenu")
                    onClicked: { page.askQuit = false; page.screen = "menu" } }
                PixelButton { width: 360; text: tr("endGame"); onClicked: page.confirmQuit = true }
            }
        }
        // end the game?
        Rectangle {
            visible: page.askQuit && page.confirmQuit
            x: 40; y: 300; width: 400; height: 220
            color: "#0c120a"; border.width: 2; border.color: "#E7FFCD"
            PixelText { anchors.horizontalCenter: parent.horizontalCenter; y: 34; text: tr("quitAsk"); pixelSize: 3 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; y: 110; spacing: 16
                PixelButton { width: 160; text: tr("yes"); onClicked: page.quitGame() }
                PixelButton { width: 160; text: tr("no"); onClicked: page.confirmQuit = false }
            }
        }
    }

    // ================= WI-FI =================
    Item {
        anchors.fill: parent
        visible: page.screen == "wifi"
        PixelText { anchors.horizontalCenter: parent.horizontalCenter; y: 40; text: tr("wifiTitle"); pixelSize: 5 }
        PixelText { x: 30; y: 110; text: tr("thisPhone"); pixelSize: 2; color: "#cfeca0" }
        Text {
            x: 30; y: 138
            text: net.localAddress != "" ? net.name + "   " + net.localAddress : net.name + "   " + tr("noWifi")
            color: "#E7FFCD"; font.family: arcade.name; font.pixelSize: 16
        }
        PixelText { x: 30; y: 176; text: tr("searching") + (page.blink ? " ..." : ""); pixelSize: 2; color: "#cfeca0" }
        Rectangle {
            x: 20; y: 198; width: 440; height: 300
            color: "#0c120a"; border.width: 2; border.color: "#5f7f45"
            Text {
                visible: page.peerList.length == 0
                x: 20; y: 20; width: 400; wrapMode: Text.WordWrap
                color: "#9cc575"; font.family: "Nokia Pure Text"; font.pixelSize: 22
                text: tr("wifiHelp")
            }
            Column {
                x: 16; y: 16; spacing: 12
                Repeater {
                    model: page.peerList
                    Rectangle {
                        width: 408; height: 60
                        color: peerArea.pressed ? "#E7FFCD" : "#0c120a"
                        border.width: 4; border.color: modelData.busy ? "#5f7f45" : "#E7FFCD"
                        Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.family: arcade.name; font.pixelSize: 16
                            color: peerArea.pressed ? "#0c120a" : (modelData.busy ? "#5f7f45" : "#E7FFCD") }
                        Text { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.busy ? tr("busy") : modelData.ip; font.family: arcade.name; font.pixelSize: 12
                            color: peerArea.pressed ? "#0c120a" : "#9cc575" }
                        MouseArea { id: peerArea; anchors.fill: parent; enabled: !modelData.busy && !net.inviting
                            onClicked: { page.sfx("move1"); net.invite(modelData.ip, modelData.port) } }
                    }
                }
            }
        }
        PixelText { x: 30; y: 520; text: tr("ipAddr"); pixelSize: 2; color: "#cfeca0" }
        TextField {
            id: ipField
            x: 20; y: 544; width: 250
            text: String(helper.setting("lastIp", "192.168.1."))
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhPreferNumbers
        }
        PixelButton {
            x: 280; y: 540; width: 180; height: 60
            text: tr("connect"); enabled: !net.inviting
            onClicked: {
                var ip = String(ipField.text).replace(/\s/g, "")
                if (!/^\d+\.\d+\.\d+\.\d+$/.test(ip)) { page.sfx("crash"); return }
                helper.setSetting("lastIp", ip)
                ipField.platformCloseSoftwareInputPanel()
                net.invite(ip, 45455)
            }
        }
        PixelButton { anchors.horizontalCenter: parent.horizontalCenter; y: 770; text: tr("back"); onClicked: page.closeWifi() }

        // our invitation is on its way
        Rectangle {
            visible: net.inviting
            x: 40; y: 260; width: 400; height: 220
            color: "#0c120a"; border.width: 2; border.color: "#E7FFCD"
            PixelText { anchors.horizontalCenter: parent.horizontalCenter; y: 40; text: tr("waitAnswer"); pixelSize: 2; color: page.blink ? "#E7FFCD" : "#cfeca0" }
            PixelButton { anchors.horizontalCenter: parent.horizontalCenter; y: 110; width: 300; text: tr("cancel"); onClicked: net.cancelInvite() }
        }
    }

    // invitation from another phone (on top of any screen except a running game)
    Rectangle {
        visible: page.inviteIn
        x: 16; y: 250; width: 448; height: 280
        color: "#0c120a"; border.width: 2; border.color: "#f0d860"
        PixelText { anchors.horizontalCenter: parent.horizontalCenter; y: 30; text: tr("invite"); pixelSize: 4; color: "#f0d860" }
        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 90; text: page.inviteName; color: "#E7FFCD"; font.family: arcade.name; font.pixelSize: 16 }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; y: 170; spacing: 12
            PixelButton { width: 206; text: tr("accept"); onClicked: page.acceptInvite() }
            PixelButton { width: 206; text: tr("decline"); onClicked: { page.inviteIn = false; net.decline() } }
        }
    }

    // ================= SCORES =================
    Item {
        anchors.fill: parent
        visible: page.screen == "stats"
        PixelText { anchors.horizontalCenter: parent.horizontalCenter; y: 60; text: tr("stats"); pixelSize: 6 }
        Rectangle {
            x: 12; y: 150; width: 456; height: 330
            color: "#0c120a"; border.width: 2; border.color: "#5f7f45"
            Column {
                x: 16; y: 20; spacing: 22
                Row {
                    Item { width: 170; height: 1 }
                    PixelText { width: 95; text: tr("won"); pixelSize: 2; color: "#9cc575" }
                    PixelText { width: 95; text: tr("lost"); pixelSize: 2; color: "#9cc575" }
                    PixelText { text: tr("bestShots"); pixelSize: 2; color: "#9cc575" }
                }
                Repeater {
                    model: ["ai0", "ai1", "ai2", "net"]
                    Row {
                        property variant st: page.stats[modelData] ? page.stats[modelData] : { w: 0, l: 0, b: 0 }
                        PixelText { width: 170; text: modelData == "net" ? "WI-FI" : tr("lv" + index); pixelSize: 3; color: "#E7FFCD" }
                        Text { width: 95; text: String(st.w); font.family: arcade.name; font.pixelSize: 20; color: "#E7FFCD" }
                        Text { width: 95; text: String(st.l); font.family: arcade.name; font.pixelSize: 20; color: "#cfeca0" }
                        Text { text: st.b > 0 ? String(st.b) : "-"; font.family: arcade.name; font.pixelSize: 20; color: "#cfeca0" }
                    }
                }
            }
            Text {
                x: 16; y: 270; width: 420; wrapMode: Text.WordWrap
                color: "#8C8C8C"; font.family: "Nokia Pure Text"; font.pixelSize: 20; text: tr("statsHelp")
            }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 690; spacing: 16
            PixelButton { width: 220; text: page.askReset ? tr("yes") : tr("clear")
                onClicked: { if (!page.askReset) { page.askReset = true; return } page.askReset = false; page.resetStats() } }
            PixelButton { width: 220; text: page.askReset ? tr("no") : tr("back")
                onClicked: { if (page.askReset) page.askReset = false; else page.screen = "menu" } }
        }
        PixelText {
            anchors.horizontalCenter: parent.horizontalCenter; y: 780
            visible: page.askReset; text: tr("resetAsk"); pixelSize: 3; color: "#ff7a6a"
        }
    }

    // ================= ABOUT =================
    Item {
        anchors.fill: parent
        visible: page.screen == "about"
        Image { anchors.horizontalCenter: parent.horizontalCenter; y: 40; source: "meeships80.png" }
        PixelText { anchors.horizontalCenter: parent.horizontalCenter; y: 140; text: tr("title"); pixelSize: 5 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; y: 186
            text: helper.version; color: "#8C8C8C"; font.family: "Nokia Pure Text"; font.pixelSize: 20
        }
        Column {
            x: 32; y: 230; width: 416; spacing: 18
            Text { width: parent.width; wrapMode: Text.WordWrap; color: "white"; font.family: "Nokia Pure Text"; font.pixelSize: 24; text: tr("aboutText") }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: "#cfeca0"; font.family: "Nokia Pure Text"; font.pixelSize: 22; text: tr("help") }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: "#9cc575"; font.family: "Nokia Pure Text"; font.pixelSize: 20; text: tr("setupHelp") }
            Text {
                width: parent.width; wrapMode: Text.WordWrap; color: "#8C8C8C"; font.family: "Nokia Pure Text"; font.pixelSize: 20
                textFormat: Text.RichText
                text: tr("credit") + "<br><a style='color:#cfeca0' href='https://github.com/smyhu'>github.com/smyhu</a>"
                onLinkActivated: Qt.openUrlExternally(link)
            }
        }
        PixelButton { anchors.horizontalCenter: parent.horizontalCenter; y: 770; text: tr("back"); onClicked: page.screen = "menu" }
    }

    // Wi-Fi dropped during a match: the game is kept and the phones reconnect by themselves
    Rectangle {
        anchors.fill: parent
        visible: page.netDown
        color: "#cc000000"
        MouseArea { anchors.fill: parent }
        Rectangle {
            x: 20; y: 260; width: 440; height: 300
            color: "#0c120a"; border.width: 2; border.color: "#ff7a6a"
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 30; spacing: 22
                PixelText { anchors.horizontalCenter: parent.horizontalCenter; text: tr("linkDown"); pixelSize: 3; color: "#ff7a6a" }
                PixelText { anchors.horizontalCenter: parent.horizontalCenter; text: tr("relinking") + (page.blink ? " ..." : "    "); pixelSize: 2; color: "#E7FFCD" }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: String(page.lostLeft); font.family: arcade.name; font.pixelSize: 24; color: "#cfeca0" }
                PixelButton { anchors.horizontalCenter: parent.horizontalCenter; width: 320; text: tr("endGame"); onClicked: page.quitGame() }
            }
        }
    }

    // short notices (connection lost, invitation declined ...)
    Rectangle {
        visible: page.toastOn
        anchors.horizontalCenter: parent.horizontalCenter
        y: 700; width: 440; height: 50
        color: "#0c120a"; border.width: 2; border.color: "#ff7a6a"
        PixelText { anchors.centerIn: parent; text: page.toast; pixelSize: 2; color: "#ff7a6a" }
    }
}
