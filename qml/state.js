.pragma library
// Live game objects kept outside QML properties (QML variant reads copy whole objects).
var me = null;        // my side under fire: G.newSide(myShips)
var view = null;      // what I know about the enemy sea: G.newView()
var aiSide = null;    // solo: the computer's fleet
var aiView = null;    // solo: what the computer knows about my sea
