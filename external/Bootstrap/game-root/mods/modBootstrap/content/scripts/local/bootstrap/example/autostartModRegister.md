# Bootstrap Autostart Register
Mods can be registered in bootstrap via an item-xml definition. This removes the
necessity for mod users to modify the bootstrap registry script manually und
thus reduces the friction of adding the mod to their installation significantly
(once bootstrap is installed).

Given the past experience with bootstrapped mod installations this method should
be the preferred method of registering mods in bootstrap.

## How this works
An "autostart" item definition must be added to your mod. Its name will tell the
internal bootstrap statemachine about your own custom startup-state which is
responsible to create/spawn/start your mod. When bootstrap mod is started (at the
beginning of a game, after a savegame is loaded or a fast-travel / world change
is finished) it will run every found autostart-state automatically.

While the end-user does not need to adjust/script-merge the bootstrapping anymore
this method requires your bootstrapped mod to have a DLC bundle which provides
the autostart item-xml definiton.

## Creating the machine state
Start by creating your main mod class (or main mod initializer class) that will
be created by the bootstrap mod:
```js
class CMyCustomBootstrappedMod extends CEntityMod {
  default modName = 'Bootstrapped mod';
  default modAuthor = "Lorem";
  default modUrl = "http://www.nexusmods.com/witcher3/mods/1234";
  default modVersion = '1.23';

  default logLevel = MLOG_DEBUG;

  // see mod_example_entitymod.ws for more info
  default template = "dlc/modtemplates/bootstrap/mycustommodentity.w2ent";

  event OnSpawned(spawnData: SEntitySpawnData) {
    super.OnSpawned(spawnData);

    GetWitcherPlayer().DisplayHudMessage("Example Entity Mod spawned");
    // add a deferred non-repeating timer method if you need to ensure other
    // data is present before doing some work
    // AddTimer('myTimerCallback', 10, false, , , , true);
  }

  // timer function myTimerCallback(deltaTime: float, id: int) {
  //
  // }
}
```
or for a non-entity Mod:
```js
class CMyCustomBootstrappedMod extends CMod {
  default modName = 'Bootstrapped mod';
  default modAuthor = "Lorem";
  default modUrl = "http://www.nexusmods.com/witcher3/mods/1234";
  default modVersion = '1.23';

  default logLevel = MLOG_DEBUG;

  public function init() {
    super.init();
    // DO STUFF
    // Note: when this mode is called the screen is still black.
  }
}
```

Then, in one of your scripts, add a state to the `CModBootstrap` statemachine
that extends the `BootstrapCreateMod` state:
```js
/**
 * To create a bootstrapped mod you must add a state to the CModBootstrap
 * statemachine. The new state must extend the BootstrapCreateMod state. This
 * state must only spawn your main class and nothing else. Defer any other
 * intialization work to your custom mod methods!
 *
 * In this example we are adding CreateMyCustomBootstrappedMod state to the
 * statemachine.
 *
 * Note that if two bootstrap mods have the same name the game won't compile.
 * For this reason you must use a unique name for your state, e.g. include your
 * mods name in the methode name.
 */
state CreateMyCustomBootstrappedMod in CModBootstrap extends BootstrapCreateMod {
  // ------------------------------------------------------------------------
  final function modCreate(): CMod {
    return new CMyCustomBootstrappedMod in parent;
  }
  // ------------------------------------------------------------------------
}
```

## Creating the autostart item register
Once you have added your state, create an utf-16 encoded (!) xml like the
following example. Note that the item name attribute must match your newly
created state name, in this example `name="CreateMyCustomBootstrappedMod"`:
```xml
<?xml version="1.0" encoding="UTF-16"?>
<redxml>
  <definitions>
    <items>

      <!--
        the name of the state to create the bootstrpped mod.
       -->
      <item name="CreateMyCustomBootstrappedMod">
        <!-- make sure to add this tag or else the autostart register won't be detected -->
        <tags>RegisterAsBootstrappedMod</tags>
      </item>

    </items>
  </definitions>
</redxml>
```
Normally, paths to new item definitions must be registered in a reddlc for the
game to pick them up. To make it easier for mod authors, bootstrap mod already
defines a default location which will be automatically searched by the game.
Put your xml definition file in a dlc bundle into the folder:

`dlc/dlcbootstrap/autostart/`

Make sure the name of the xml is globally unique by using your modname as part
of the filename, e.g. `start_mycustommodname.xml`.

## Testing
Bootstrap mod will log the spawn of every mod that was registered. Make sure
your defined `modName` is somewhere among the started mods in the log file.

## Credits
Credits for discovering the method go to [@Aeltoth](https://www.nexusmods.com/witcher3/users/89683013)!
