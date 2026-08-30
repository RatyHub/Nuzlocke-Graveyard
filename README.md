# Nuzlocke Graveyard

## 🇫🇷 Français

### Introduction

Nuzlocke Graveyard est un plugin PSDK qui ajoute une interface permettant de consulter le cimetière Nuzlocke de la sauvegarde en cours.

Le plugin est rétrocompatible : les Pokémon déjà présents dans le cimetière avant son installation seront également affichés.

### Fonctionnalités

- affiche la liste des Pokémon morts, du plus récent au plus ancien ;
- permet de consulter le Résumé de chaque Pokémon.

### Mode d'affichage

L'interface utilise le mode `:dex` par défaut. Deux modes sont disponibles :

- `:dex` : présentation inspirée du Pokédex ;
- `:party` : présentation inspirée du menu Équipe.

Pour utiliser le mode `:party`, ajoutez ce monkey patch dans un script Ruby chargé après le script du plugin :

```ruby
module NuzlockeGraveyard
  remove_const(:MODE)
  MODE = :party
end
```

Le monkey patch doit être chargé après `001 Nuzlocke Graveyard.rb`, afin que le module et sa constante soient déjà définis.

### Installation

Placez le fichier `.psdkplug` dans le dossier `scripts` du projet.

Au démarrage, le Plugin Manager de PSDK installe le plugin automatiquement.

### Assets graphiques

Les assets propres au plugin se trouvent dans `graphics/interface/nuzlocke_graveyard` :

- `frame.png` : bandeau supérieur utilisé dans les deux modes ;
- `button_fr.png` : bouton représentant un Pokémon en mode `:dex` lorsque le jeu est en français ;
- `button_en.png` : bouton représentant un Pokémon en mode `:dex` lorsque le jeu est en anglais ou dans une autre langue.

Le mode `:party` réutilise les boutons natifs du menu Équipe de PSDK.

### Commande d'ouverture

L'interface peut être ouverte depuis un événement avec la commande suivante :

```ruby
GamePlay.open_nuzlocke_graveyard
```

## 🇬🇧 English

### Introduction

Nuzlocke Graveyard is a PSDK plugin that adds an interface for viewing the Nuzlocke graveyard of the current save file.

The plugin is backward-compatible: Pokémon that were already in the graveyard before installation will also be displayed.

### Features

- displays the list of deceased Pokémon, from newest to oldest;
- lets you view each Pokémon's Summary screen.

### Display mode

The interface uses `:dex` mode by default. Two modes are available:

- `:dex`: a layout inspired by the Pokédex;
- `:party`: a layout inspired by the Party menu.

To use `:party` mode, add this monkey patch to a Ruby script loaded after the plugin script:

```ruby
module NuzlockeGraveyard
  remove_const(:MODE)
  MODE = :party
end
```

The monkey patch must be loaded after `001 Nuzlocke Graveyard.rb`, so the module and its constant are already defined.

### Installation

Place the `.psdkplug` file in the project's `scripts` folder.

On startup, PSDK's Plugin Manager installs the plugin automatically.

### Graphic assets

The plugin-specific assets are located in `graphics/interface/nuzlocke_graveyard`:

- `frame.png`: top frame used in both modes;
- `button_fr.png`: Pokémon button used in `:dex` mode when the game is in French;
- `button_en.png`: Pokémon button used in `:dex` mode when the game is in English or another language.

The `:party` mode reuses PSDK's native Party menu buttons.

### Opening command

The interface can be opened from an event with the following command:

```ruby
GamePlay.open_nuzlocke_graveyard
```
