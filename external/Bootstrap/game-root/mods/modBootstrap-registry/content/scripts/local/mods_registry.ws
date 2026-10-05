// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
class CModRegistry extends CModFactory {
    protected function createMods() {
        // add mod creation calls here, like this:
        //
        // add(modCreate_<ModName>());
        // ...
        add(createAutoDriver());

        // see example dir
        //add(modCreate_ExampleMod());
        //add(modCreate_ExampleEntityMod());
        //add(modCreate_UiExampleMod());
    }
}
// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
