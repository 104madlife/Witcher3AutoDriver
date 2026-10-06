// ----------------------------------------------------------------------------
quest function modStartBootstrap() {
    var bootstrap: CModBootstrap;
    var entity : CEntity;
    var template : CEntityTemplate;

    // bootstrap as entity makes sure it survives fast travel in same hub
    template = (CEntityTemplate)LoadResource("dlc/modtemplates/bootstrap/bootstrap.w2ent", true);
    entity = theGame.CreateEntity(template,
        thePlayer.GetWorldPosition(), thePlayer.GetWorldRotation());

    bootstrap = (CModBootstrap)entity;
    bootstrap.bootstrap();
}
// ----------------------------------------------------------------------------
quest function modIsBootstrapStarted(): bool {
    return FactsQuerySum("bootstrap_started") > 0;
}
// ----------------------------------------------------------------------------
// ----------------------------------------------------------------------------
statemachine class CModBootstrap extends CEntity {
    protected var modVersion : CName;
    default modVersion = '0.5';
    // ------------------------------------------------------------------------
    protected var modRegistry: CModRegistry;
    protected var log: CModLogger;
    // ------------------------------------------------------------------------
    private var itemModStates: array<name>;
    protected var itemMods: array<CMod>;
    // ------------------------------------------------------------------------
    public function bootstrap() {
        log = new CModLogger in this;
        log.init('ModBootstrap', MLOG_DEBUG);

        log.info("bootstrap v" + NameToString(modVersion) + " started");
        // create + initialize all registered mods (scripts and entity mods)
        modRegistry = new CModRegistry in this;
        modRegistry.init();

        initMods();

        FactsRemove("bootstrap_started");
        FactsAdd("bootstrap_started", 1);
    }
    // ------------------------------------------------------------------------
    private function createEntitymod(path: String) : CEntity {
        var ent : CEntity;
        var template : CEntityTemplate;

        template = (CEntityTemplate)LoadResource(path, true);
        ent = theGame.CreateEntity(template,
            thePlayer.GetWorldPosition(), thePlayer.GetWorldRotation());

        return ent;
    }
    // ------------------------------------------------------------------------
    private function initMods() {
        log.info("bootstrapping registered mods...");

        this.spawnMods(modRegistry.getMods());
        this.startItemModsRegistering();
    }
    // ------------------------------------------------------------------------
    private function spawnMods(mods: array<CMod>) {
        var entityMod: CEntityMod;
        var i: int;

        for (i = 0; i < mods.Size(); i += 1) {
            entityMod = (CEntityMod)mods[i];

            if (entityMod) {
                entityMod.setModEntity(createEntitymod(entityMod.getTemplate()));
            }
            mods[i].init();

            // show/log some info about creation
            log.info("spawned mod: " + mods[i].getModInfo());
        }
    }
    // ------------------------------------------------------------------------
    // Starts the process of registering mods that are declared through the fake
    // item technique.
    private function startItemModsRegistering() {
        var testedState: name;
        var registeredStates: array<name>;
        var i: int;

        // 0. start by filling the array of state the statemachine will go through.
        registeredStates = theGame
            .GetDefinitionsManager()
            .GetItemsWithTag('RegisterAsBootstrappedMod');

        // 1. filter invalid states
        for (i = 0; i < registeredStates.Size(); i += 1) {
            testedState = registeredStates[i];
            if (this.GetState(testedState)) {
                this.itemModStates.PushBack(testedState);
            } else {
                log.error("found invalid state in autostart registry: " + testedState);
            }
        }

        // 2. start the statemachine:
        this.GotoState('BootstrapWaiting');
    }
    // ------------------------------------------------------------------------
    protected function registerItemMod(mod: CMod) {
        this.itemMods.PushBack(mod);
    }
    // ------------------------------------------------------------------------
    protected function hasItemModState(): bool {
        return this.itemModStates.Size() > 0;
    }
    // ------------------------------------------------------------------------
    protected function getNextItemModState(): name {
        return this.itemModStates.PopBack();
    }
    // ------------------------------------------------------------------------
    protected function finishItemModsRegistering() {
        this.spawnMods(this.itemMods);
    }
    // ------------------------------------------------------------------------
}
// ----------------------------------------------------------------------------
// This state is offered as a base state/class mod authors should extend to
// override the `modCreate()` function.
abstract state BootstrapCreateMod in CModBootstrap {
    event OnEnterState(previous_state_name: name) {
        super.OnEnterState(previous_state_name);

        this.register(this.modCreate());
        this.finish();
    }

    public function modCreate(): CMod;

    private final function register(mod: CMod) {
        parent.itemMods.PushBack(mod);
    }

    private final function finish() {
        parent.GotoState('BootstrapWaiting');
    }
}
// ----------------------------------------------------------------------------
state BootstrapWaiting in CModBootstrap {
    event OnEnterState(previous_state_name: name) {
        super.OnEnterState(previous_state_name);
        this.Waiting_main();
    }

    entry function Waiting_main() {
        if (parent.hasItemModState()) {
            parent.GotoState(parent.getNextItemModState());
        }
        else {
            // once the ItemMods pool is emptied we move the statemachine to the
            // 'Completed' state.
            parent.GotoState('BootstrapCompleted');
        }
    }
}
// ----------------------------------------------------------------------------
state BootstrapCompleted in CModBootstrap {
    event OnEnterState(previous_state_name: name) {
        super.OnEnterState(previous_state_name);
        this.Completed_main();
    }

    entry function Completed_main() {
        parent.finishItemModsRegistering();
    }
}
// ----------------------------------------------------------------------------
abstract class CModFactory {
    private var mods: array<CMod>;

    protected function createMods();

    public final function init() { createMods(); }

    protected final function add(mod: CMod) { mods.PushBack(mod); }

    public final function getMods() : array<CMod> { return mods; }
}
// ----------------------------------------------------------------------------
