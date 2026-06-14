# LX49+ Mapper pour REAPER

Prototype ReaScript + JSFX pour apprendre et mapper les potards, faders et boutons d'un Nektar Impact LX49+ dans REAPER.

## Contenu

- `LX49plus_CC_Bridge.jsfx` : petit JSFX à insérer sur une piste MIDI. Il lit les CC entrants et les publie dans une mémoire partagée `gmem`.
- `LX49plus_GUI_Mapper.lua` : interface graphique native REAPER (`gfx`) pour apprendre les CC et les mapper vers des pistes, le master ou des actions REAPER.

## Installation

1. Dans REAPER : `Options > Show REAPER resource path in explorer/finder`.
2. Copie `LX49plus_CC_Bridge.jsfx` dans le dossier `Effects`.
3. Copie `LX49plus_GUI_Mapper.lua` dans le dossier `Scripts`.
4. Redémarre REAPER ou lance `FX browser > Scan for new plugins` si le JSFX n'apparaît pas.
5. Dans REAPER : `Actions > Show action list > ReaScript > Load...`, puis choisis `LX49plus_GUI_Mapper.lua`.

## Piste MIDI bridge

Crée une piste dédiée nommée par exemple `LX49+ CONTROL` :

1. Input MIDI : `Impact LX49+ > All channels`.
2. Record arm : ON.
3. Record monitoring : ON.
4. FX : ajoute `JS: LX49+ CC Bridge to ReaScript`.

Le script Lua ne reçoit pas directement le MIDI brut de REAPER : le JSFX sert de pont fiable entre le flux MIDI de la piste et l'interface graphique.

## Utilisation

1. Lance `LX49plus_GUI_Mapper.lua` depuis l'Action List.
2. Clique un fader, potard ou bouton dans l'interface.
3. Clique `Apprendre CC`.
4. Bouge le contrôle physique correspondant sur le LX49+.
5. Clique `Changer cible` pour choisir la destination : volume piste, pan piste, master, mute/solo/arm ou action REAPER.
6. Clique `Configurer argument` pour choisir le numéro de piste ou l'ID d'action.

## Notes

- Les mappings sont sauvegardés dans l'ExtState REAPER et reviennent au prochain lancement.
- Les volumes sont mappés de -60 dB à 0 dB, ce qui évite les boosts accidentels.
- Les actions se déclenchent uniquement au passage au-dessus de 64, pratique pour les boutons qui envoient 127 à l'appui puis 0 au relâchement.
- Si rien ne bouge dans l'interface, vérifie la piste bridge : armée, monitoring ON, entrée MIDI du LX49+ activée, JSFX chargé.
