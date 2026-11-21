import QtQuick 1.1
import QtMultimediaKit 1.1

// MeeShips 8-bit sounds: shared games-common ones + own (tools/make-ship-sounds.py).
// Loaded through a Loader: if QtMultimediaKit is missing the game simply stays silent.
Item {
    function play(name) {
        if (name == "shot") shot.play();
        else if (name == "splash") splash.play();
        else if (name == "hit") hit.play();
        else if (name == "sunk") sunk.play();
        else if (name == "start") start.play();
        else if (name == "move1") move1.play();
        else if (name == "move2") move2.play();
        else if (name == "eat") eat.play();
        else if (name == "bonus") bonus.play();
        else if (name == "crash") crash.play();
        else if (name == "gameover") gameover.play();
        else if (name == "record") record.play();
    }
    SoundEffect { id: shot; source: "sounds/shot.wav" }
    SoundEffect { id: splash; source: "sounds/splash.wav" }
    SoundEffect { id: hit; source: "sounds/hit.wav" }
    SoundEffect { id: sunk; source: "sounds/sunk.wav" }
    SoundEffect { id: start; source: "sounds/start.wav" }
    SoundEffect { id: move1; source: "sounds/move1.wav"; volume: 0.6 }
    SoundEffect { id: move2; source: "sounds/move2.wav"; volume: 0.6 }
    SoundEffect { id: eat; source: "sounds/eat.wav" }
    SoundEffect { id: bonus; source: "sounds/bonus.wav" }
    SoundEffect { id: crash; source: "sounds/crash.wav" }
    SoundEffect { id: gameover; source: "sounds/gameover.wav" }
    SoundEffect { id: record; source: "sounds/record.wav" }
}
