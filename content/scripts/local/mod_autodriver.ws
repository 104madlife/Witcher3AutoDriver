// ----------------------------------------------------------------------------
// AutoDriver prototype
// ----------------------------------------------------------------------------
statemachine class CModAutoDriver extends CMod {
    default modName = 'AutoDriver';
    default modAuthor = "104madlife";
    default modUrl = "local";
    default modVersion = '0.1';

    default logLevel = MLOG_DEBUG;

    protected var minWalkDistance: float; default minWalkDistance = 8.0;
    protected var maxWalkDistance: float; default maxWalkDistance = 18.0;
    protected var minHorseDistance: float; default minHorseDistance = 12.0;
    protected var maxHorseDistance: float; default maxHorseDistance = 28.0;

    protected var walkSpeed: float; default walkSpeed = 1.0;
    protected var horseSpeed: float; default horseSpeed = 2.0;

    protected var walkArrivalDistance: float; default walkArrivalDistance = 3.0;
    protected var walkTargetTimeout: float; default walkTargetTimeout = 8.0;
    protected var walkTickInterval: float; default walkTickInterval = 0.5;
    protected var walkStuckDistance: float; default walkStuckDistance = 0.75;
    protected var walkStuckTimeout: float; default walkStuckTimeout = 3.0;
    protected var walkTargetCandidates: int; default walkTargetCandidates = 12;
    protected var walkSafeSpotPersonalSpace: float; default walkSafeSpotPersonalSpace = 0.5;
    protected var walkSafeSpotSearchRadius: float; default walkSafeSpotSearchRadius = 5.0;
    protected var godOxygenTickInterval: float; default godOxygenTickInterval = 0.25f;
    protected var randomTeleportMinRadius: float; default randomTeleportMinRadius = 20.0f;
    protected var randomTeleportMaxRadius: float; default randomTeleportMaxRadius = 100.0f;
    protected var randomTeleportSafeRadius: float; default randomTeleportSafeRadius = 6.0f;
    protected var randomTeleportPersonalSpace: float; default randomTeleportPersonalSpace = 1.0f;
    protected var randomTeleportZRange: float; default randomTeleportZRange = 20.0f;
    protected var randomTeleportMaxVerticalDelta: float; default randomTeleportMaxVerticalDelta = 50.0f;
    protected var randomTeleportStreamingDelay: float; default randomTeleportStreamingDelay = 2.0f;
    protected var randomTeleportAttempts: int; default randomTeleportAttempts = 20;
    protected var horseTransitionTimeout: float; default horseTransitionTimeout = 5.0f;
    protected var horseTransitionPollInterval: float; default horseTransitionPollInterval = 0.05f;
    protected var horseSummonTimeout: float; default horseSummonTimeout = 10.0f;
    protected var horseImmediateMountMaxDistance: float; default horseImmediateMountMaxDistance = 20.0f;
    protected var teleportVerificationDelay: float; default teleportVerificationDelay = 0.15f;
    protected var teleportVerificationAttempts: int; default teleportVerificationAttempts = 3;
    protected var teleportArrivalTolerance: float; default teleportArrivalTolerance = 5.0f;
    protected var godModeEnabled: bool;

    protected var hasWalkTarget: bool;
    protected var currentWalkTarget: Vector;
    protected var walkTargetIssuedAt: float;
    protected var lastWalkPosition: Vector;
    protected var lastWalkProgressAt: float;
    public function init() {
        super.init();

        disableEquipmentDurabilityProtection();

        theInput.RegisterListener(this, 'OnToggleWalkWander', 'AutoDriver_WalkWander');
        theInput.RegisterListener(this, 'OnToggleHorseRide', 'AutoDriver_ToggleHorse');
        theInput.RegisterListener(this, 'OnToggleHorseWander', 'AutoDriver_HorseWander');
        theInput.RegisterListener(this, 'OnToggleGodMode', 'AutoDriver_GodMode');
        theInput.RegisterListener(this, 'OnOfficialTeleport', 'AutoDriver_OfficialTeleport');
        theInput.RegisterListener(this, 'OnRandomXYTeleport', 'AutoDriver_RandomXYTeleport');

        GotoState('AutoDriver_Idle');
        notify("AutoDriver loaded: NumPad6 horse toggle, NumPad7 god, NumPad8/9 teleport");
    }

    protected function notify(message: String) {
        GetWitcherPlayer().DisplayHudMessage(message);
        log.info(message);
    }

    protected function enableGodMode() {
        godModeEnabled = true;
        thePlayer.SetImmortalityMode(AIM_Invulnerable, AIC_Default, true);
        maintainGodModeOxygen();
        notify("AutoDriver god mode ON: no health damage, " + IntToString(enableEquipmentDurabilityProtection()) + " items protected");
    }

    protected function disableGodMode() {
        godModeEnabled = false;
        thePlayer.SetImmortalityMode(AIM_None, AIC_Default, true);
        notify("AutoDriver god mode OFF: " + IntToString(disableEquipmentDurabilityProtection()) + " item protections removed");
    }

    protected function enableEquipmentDurabilityProtection() : int {
        var items: array<SItemUniqueId>;
        var item: SItemUniqueId;
        var i, protectedCount: int;

        if (!thePlayer) {
            return 0;
        }

        thePlayer.inv.GetAllItems(items);
        for (i = 0; i < items.Size(); i += 1) {
            item = items[i];
            if (!thePlayer.inv.IsIdValid(item) || !thePlayer.inv.HasItemDurability(item)) {
                continue;
            }

            if (thePlayer.inv.GetItemModifierInt(item, 'AutoDriverIndestructible', 0) > 0) {
                if (!thePlayer.inv.ItemHasAbility(item, 'MA_Indestructible')) {
                    thePlayer.inv.AddItemCraftedAbility(item, 'MA_Indestructible', false);
                }
                protectedCount += 1;
            } else if (!thePlayer.inv.ItemHasAbility(item, 'MA_Indestructible')) {
                thePlayer.inv.AddItemCraftedAbility(item, 'MA_Indestructible', false);
                thePlayer.inv.SetItemModifierInt(item, 'AutoDriverIndestructible', 1);
                protectedCount += 1;
            }
        }

        return protectedCount;
    }

    protected function disableEquipmentDurabilityProtection() : int {
        var items: array<SItemUniqueId>;
        var item: SItemUniqueId;
        var i, removedCount: int;

        if (!thePlayer) {
            return 0;
        }

        thePlayer.inv.GetAllItems(items);
        for (i = 0; i < items.Size(); i += 1) {
            item = items[i];
            if (!thePlayer.inv.IsIdValid(item) || thePlayer.inv.GetItemModifierInt(item, 'AutoDriverIndestructible', 0) <= 0) {
                continue;
            }

            if (thePlayer.inv.ItemHasAbility(item, 'MA_Indestructible')) {
                thePlayer.inv.RemoveItemCraftedAbility(item, 'MA_Indestructible');
            }
            thePlayer.inv.SetItemModifierInt(item, 'AutoDriverIndestructible', 0);
            removedCount += 1;
        }

        return removedCount;
    }

    protected function maintainGodModeOxygen() {
        if (!godModeEnabled || !thePlayer) {
            return;
        }

        thePlayer.ForceSetStat(BCS_Air, thePlayer.GetStatMax(BCS_Air));
        if (thePlayer.HasBuff(EET_Drowning)) {
            thePlayer.RemoveBuff(EET_Drowning);
        }
    }

    protected latent function waitForHorseStatus(targetStatus: EVehicleMountStatus) : bool {
        var riderData: CAIStorageRiderData;
        var timeoutAt: float;
        var result: bool;

        riderData = thePlayer.GetRiderData();
        if (!riderData) {
            return false;
        }

        timeoutAt = theGame.GetEngineTimeAsSeconds() + horseTransitionTimeout;
        while (theGame.GetEngineTimeAsSeconds() < timeoutAt) {
            if (riderData.GetRidingManagerCurrentTask() == RMT_None
                && riderData.sharedParams.mountStatus == targetStatus) {
                result = true;
                return result;
            }

            if (riderData.ridingManagerMountError) {
                return false;
            }

            Sleep(horseTransitionPollInterval);
        }

        return false;
    }

    protected function getCurrentHorseEntity() : CNewNPC {
        var horse: CNewNPC;
        var horseComponent: W3HorseComponent;

        horse = thePlayer.GetHorseCurrentlyMounted();
        if (horse) {
            return horse;
        }

        horseComponent = thePlayer.GetUsedHorseComponent();
        if (horseComponent) {
            horse = (CNewNPC)horseComponent.GetEntity();
        }

        return horse;
    }

    protected function isPlayerHorseReadyToMount(horse: CNewNPC) : bool {
        if (!horse || !horse.IsAlive()) {
            return false;
        }

        return VecDistanceSquared(thePlayer.GetWorldPosition(), horse.GetWorldPosition())
            <= horseImmediateMountMaxDistance * horseImmediateMountMaxDistance;
    }

    protected latent function waitForNearbyPlayerHorse(out horse: CNewNPC) : bool {
        var timeoutAt: float;

        timeoutAt = theGame.GetEngineTimeAsSeconds() + horseSummonTimeout;
        while (theGame.GetEngineTimeAsSeconds() < timeoutAt) {
            horse = thePlayer.GetHorseWithInventory();
            if (isPlayerHorseReadyToMount(horse)) {
                return true;
            }

            Sleep(horseTransitionPollInterval);
        }

        return false;
    }

    protected latent function performHorseToggle() : bool {
        var riderData: CAIStorageRiderData;
        var horse: CNewNPC;
        var status: EVehicleMountStatus;
        var completed: bool;
        var horseReady: bool;

        if (!thePlayer || theGame.IsDialogOrCutscenePlaying()
            || theGame.IsFading() || theGame.IsBlackscreen()) {
            notify("AutoDriver horse toggle blocked by current game state");
            return false;
        }

        riderData = thePlayer.GetRiderData();
        if (!riderData) {
            notify("AutoDriver horse toggle failed: rider data unavailable");
            return false;
        }

        status = riderData.sharedParams.mountStatus;
        if (status == VMS_mounted) {
            horse = getCurrentHorseEntity();
            if (!horse) {
                notify("AutoDriver dismount failed: mounted horse unavailable");
                return false;
            }

            notify("AutoDriver dismounting horse");
            thePlayer.DismountVehicle(horse, DT_instant);
            completed = waitForHorseStatus(VMS_dismounted);
            if (completed) {
                notify("AutoDriver horse dismount complete");
            } else {
                notify("AutoDriver horse dismount timed out");
            }
            return completed;
        }

        if (status == VMS_dismountInProgress) {
            completed = waitForHorseStatus(VMS_dismounted);
            if (completed) {
                notify("AutoDriver horse dismount complete");
            } else {
                notify("AutoDriver horse dismount timed out");
            }
            return completed;
        }

        if (status == VMS_mountInProgress) {
            notify("AutoDriver horse mount already in progress");
            completed = waitForHorseStatus(VMS_mounted);
            return completed;
        }

        if (thePlayer.IsInCombat() || thePlayer.IsInInterior() || thePlayer.IsInAir()
            || thePlayer.IsSwimming() || thePlayer.IsDiving()
            || thePlayer.IsSailing() || thePlayer.IsUsingBoat()) {
            notify("AutoDriver horse mount blocked by current player state");
            return false;
        }

        horse = thePlayer.GetHorseWithInventory();
        horseReady = isPlayerHorseReadyToMount(horse);
        if (!horseReady) {
            notify("AutoDriver calling nearby horse");
            theGame.OnSpawnPlayerHorse();
            horseReady = waitForNearbyPlayerHorse(horse);
        }

        if (!horseReady) {
            notify("AutoDriver horse summon timed out");
            return false;
        }

        notify("AutoDriver mounting horse");
        thePlayer.MountVehicle(horse, VMT_ImmediateUse, EVS_driver_slot);
        completed = waitForHorseStatus(VMS_mounted);
        if (completed) {
            notify("AutoDriver horse mount complete");
        } else {
            notify("AutoDriver horse mount timed out");
        }
        return completed;
    }

    protected latent function prepareTeleportForTravel(out reason: String) : bool {
        var riderData: CAIStorageRiderData;
        var horse: CNewNPC;
        var status: EVehicleMountStatus;
        var completed: bool;
        var allowed: bool;

        allowed = canUseTeleport(reason);
        if (!allowed) {
            return false;
        }

        horse = getCurrentHorseEntity();
        if (!horse) {
            return true;
        }

        riderData = thePlayer.GetRiderData();
        if (!riderData) {
            reason = "rider data unavailable";
            return false;
        }

        status = riderData.sharedParams.mountStatus;
        if (status == VMS_mountInProgress) {
            reason = "horse mount is in progress";
            return false;
        }

        if (status == VMS_mounted) {
            notify("AutoDriver teleport: dismounting horse first");
            thePlayer.DismountVehicle(horse, DT_instant);
        }

        if (status == VMS_mounted || status == VMS_dismountInProgress) {
            completed = waitForHorseStatus(VMS_dismounted);
            if (!completed) {
                reason = "horse dismount timed out";
                return false;
            }
        }

        allowed = canUseTeleport(reason);
        return allowed;
    }

    protected function canUseTeleport(out reason: String) : bool {
        if (!thePlayer) {
            reason = "player unavailable";
            return false;
        }

        if (thePlayer.IsInGameplayScene() || theGame.IsCurrentlyPlayingNonGameplayScene()) {
            reason = "a story scene is active";
            return false;
        }

        return true;
    }

    protected latent function teleportPlayerAndVerify(
        position: Vector,
        rotation: EulerAngles,
        operation: String
    ) : bool {
        var attempt: int;
        var toleranceSquared: float;
        var distanceSquared: float;

        toleranceSquared = teleportArrivalTolerance * teleportArrivalTolerance;
        for (attempt = 0; attempt < teleportVerificationAttempts; attempt += 1) {
            thePlayer.TeleportWithRotation(position, rotation);
            Sleep(teleportVerificationDelay);

            distanceSquared = VecDistanceSquared(thePlayer.GetWorldPosition(), position);
            if (distanceSquared <= toleranceSquared) {
                return true;
            }

            log.debug(operation + " retry=" + IntToString(attempt + 1)
                + " distanceSquared=" + FloatToString(distanceSquared));
        }

        log.error(operation + " position verification failed target=" + VecToString(position)
            + " actual=" + VecToString(thePlayer.GetWorldPosition())
            + " distanceSquared=" + FloatToString(distanceSquared));
        return false;
    }

    protected function formatFastTravelPin(pin: SAvailableFastTravelMapPin, index: int, total: int) : String {
        return IntToString(index + 1) + "/" + IntToString(total)
            + " tag=" + NameToString(pin.tag)
            + " type=" + NameToString(pin.type)
            + " area=" + pin.area;
    }

    protected latent function performOfficialTeleport() : bool {
        var manager: CCommonMapManager;
        var pins: array<SAvailableFastTravelMapPin>;
        var pin: SAvailableFastTravelMapPin;
        var index: int;
        var nextIndex: int;
        var worldPath: String;
        var currentWorldPath: String;
        var position: Vector;
        var rotation: EulerAngles;
        var positionResolved: bool;
        var landPoint: bool;
        var details: String;
        var reason: String;
        var teleported: bool;

        if (!canUseTeleport(reason)) {
            notify("AutoDriver teleport blocked: " + reason);
            return false;
        }

        manager = theGame.GetCommonMapManager();
        pins = manager.GetFastTravelPoints(false, false, false, false, false);
        if (pins.Size() == 0) {
            notify("AutoDriver official teleport list is empty");
            return false;
        }

        index = FactsQuerySum("autodriver_official_teleport_index");
        if (index < 0 || index >= pins.Size()) {
            index = 0;
        }

        pin = pins[index];
        details = formatFastTravelPin(pin, index, pins.Size());
        worldPath = manager.GetWorldPathFromAreaType(pin.area);
        currentWorldPath = theGame.GetWorld().GetDepotPath();
        landPoint = pin.type == 'RoadSign';

        if (StrLen(worldPath) == 0) {
            notify("AutoDriver unknown teleport world: " + details);
            log.error("official teleport failed: " + details + " worldPath=<empty>");
            return false;
        }

        positionResolved = manager.GetFastTravelPointPosition(worldPath, pin.tag, landPoint, position, rotation);
        nextIndex = index + 1;
        if (nextIndex >= pins.Size()) {
            nextIndex = 0;
        }

        rotation.Pitch = 0.0f;
        rotation.Roll = 0.0f;

        if (worldPath == currentWorldPath) {
            if (!positionResolved) {
                notify("AutoDriver local teleport position failed: " + details);
                log.error("official teleport local failed: " + details + " worldPath=" + worldPath);
                return false;
            }

            FactsSet("autodriver_official_teleport_index", nextIndex, -1);
            log.info("official teleport local: " + details + " worldPath=" + worldPath
                + " position=" + VecToString(position) + " resolved=true issued=true");
            notify("AutoDriver official teleport: " + details);
            teleported = teleportPlayerAndVerify(position, rotation, "official local teleport");
            if (!teleported) {
                notify("AutoDriver local teleport was overridden by current player state");
                return false;
            }
            return teleported;
        }

        FactsSet("autodriver_official_teleport_index", nextIndex, -1);
        if (positionResolved) {
            log.info("official teleport global: " + details + " worldPath=" + worldPath
                + " position=" + VecToString(position) + " resolved=true issued=true");
            notify("AutoDriver cross-world teleport: " + details);
            theGame.ScheduleWorldChangeToPosition(worldPath, position, rotation);
        } else {
            log.info("official teleport global fallback: " + details + " worldPath=" + worldPath
                + " resolved=false issued=true");
            notify("AutoDriver cross-world map-pin fallback: " + details);
            theGame.ScheduleWorldChangeToMapPin(worldPath, pin.tag);
        }

        return true;
    }

    protected function getCurrentWorldRoadSignAnchors(out anchors: array<SAvailableFastTravelMapPin>) : bool {
        var manager: CCommonMapManager;
        var pins: array<SAvailableFastTravelMapPin>;
        var currentWorldPath: String;
        var pinWorldPath: String;
        var i: int;

        manager = theGame.GetCommonMapManager();
        pins = manager.GetFastTravelPoints(false, false, false, false, false);
        currentWorldPath = theGame.GetWorld().GetDepotPath();

        for (i = 0; i < pins.Size(); i += 1) {
            if (pins[i].type != 'RoadSign') {
                continue;
            }

            pinWorldPath = manager.GetWorldPathFromAreaType(pins[i].area);
            if (pinWorldPath == currentWorldPath) {
                anchors.PushBack(pins[i]);
            }
        }

        return anchors.Size() > 0;
    }

    protected function findRandomSafeTeleportPosition(anchor: Vector, out target: Vector) : bool {
        var world: CWorld;
        var mac: CMovingAgentComponent;
        var candidate: Vector;
        var safePosition: Vector;
        var correctedPosition: Vector;
        var correctedZ: float;
        var physicsZ: float;
        var i: int;

        world = theGame.GetWorld();
        mac = thePlayer.GetMovingAgentComponent();
        if (!world || !mac) {
            return false;
        }

        for (i = 0; i < randomTeleportAttempts; i += 1) {
            candidate = anchor + VecRingRand(randomTeleportMinRadius, randomTeleportMaxRadius);
            candidate.Z = anchor.Z;

            if (!world.NavigationFindSafeSpot(
                candidate,
                randomTeleportPersonalSpace,
                randomTeleportSafeRadius,
                safePosition
            )) {
                continue;
            }

            if (!world.NavigationComputeZ(
                safePosition,
                anchor.Z - randomTeleportZRange,
                anchor.Z + randomTeleportZRange,
                correctedZ
            )) {
                continue;
            }

            safePosition.Z = correctedZ;
            if (!world.NavigationFindSafeSpot(
                safePosition,
                randomTeleportPersonalSpace,
                randomTeleportSafeRadius,
                correctedPosition
            )) {
                continue;
            }

            if (AbsF(correctedPosition.Z - anchor.Z) > randomTeleportMaxVerticalDelta) {
                continue;
            }

            if (!mac.IsPositionValid(correctedPosition)) {
                continue;
            }

            if (world.PhysicsCorrectZ(correctedPosition, physicsZ)) {
                correctedPosition.Z = physicsZ;
                if (!mac.IsPositionValid(correctedPosition)) {
                    continue;
                }
            }

            target = correctedPosition;
            return true;
        }

        return false;
    }

    protected latent function performRandomXYTeleport() : bool {
        var manager: CCommonMapManager;
        var anchors: array<SAvailableFastTravelMapPin>;
        var anchorPin: SAvailableFastTravelMapPin;
        var anchorIndex: int;
        var currentWorldPath: String;
        var anchorPosition: Vector;
        var targetPosition: Vector;
        var rotation: EulerAngles;
        var reason: String;
        var result: bool;
        var ready: bool;

        ready = prepareTeleportForTravel(reason);
        if (!ready) {
            notify("AutoDriver random teleport blocked: " + reason);
            return false;
        }

        if (!getCurrentWorldRoadSignAnchors(anchors)) {
            notify("AutoDriver found no current-world RoadSign anchor");
            return false;
        }

        manager = theGame.GetCommonMapManager();
        currentWorldPath = theGame.GetWorld().GetDepotPath();
        anchorIndex = RandRange(anchors.Size());
        anchorPin = anchors[anchorIndex];

        if (!manager.GetFastTravelPointPosition(
            currentWorldPath,
            anchorPin.tag,
            true,
            anchorPosition,
            rotation
        )) {
            notify("AutoDriver failed to resolve random anchor " + NameToString(anchorPin.tag));
            return false;
        }

        rotation.Pitch = 0.0f;
        rotation.Roll = 0.0f;
        notify("AutoDriver random XY anchor: " + NameToString(anchorPin.tag));
        log.info("random XY anchor tag=" + NameToString(anchorPin.tag)
            + " position=" + VecToString(anchorPosition));
        result = teleportPlayerAndVerify(anchorPosition, rotation, "random XY anchor teleport");
        if (!result) {
            notify("AutoDriver random anchor teleport was overridden by current player state");
            return false;
        }

        Sleep(randomTeleportStreamingDelay);

        if (!findRandomSafeTeleportPosition(anchorPosition, targetPosition)) {
            notify("AutoDriver random XY validation failed; staying at safe anchor");
            log.error("random XY failed around anchor=" + NameToString(anchorPin.tag));
            return false;
        }

        rotation = thePlayer.GetWorldRotation();
        rotation.Pitch = 0.0f;
        rotation.Roll = 0.0f;
        result = teleportPlayerAndVerify(targetPosition, rotation, "random XY final teleport");
        if (!result) {
            notify("AutoDriver random XY teleport was overridden by current player state");
            return false;
        }
        notify("AutoDriver random XY teleport complete");
        log.info("random XY success anchor=" + NameToString(anchorPin.tag)
            + " target=" + VecToString(targetPosition));
        return result;
    }

    protected function stopAutoDriverActivityForTeleport() {
        resetWalkTarget();
    }

    protected function stopCurrentAction() {
        var horse: CActor;
        var mac: CMovingAgentComponent;

        thePlayer.ActionCancelAll();
        stopAutoDriverActivityForTeleport();

        mac = thePlayer.GetMovingAgentComponent();
        if (mac) {
            mac.SetGameplayRelativeMoveSpeed(0.0f);
        }

        if (thePlayer.IsUsingHorse(true)) {
            horse = (CActor)thePlayer.GetUsedVehicle();
            if (horse) {
                horse.ActionCancelAll();
            }
        }
    }

    protected function randomGroundPosition(origin: Vector, minDistance: float, maxDistance: float) : Vector {
        var result: Vector;
        var groundZ: float;
        var world: CWorld;

        world = theGame.GetWorld();
        result = origin + VecRingRand(minDistance, maxDistance);

        if (world.NavigationComputeZ(result, result.Z - 8.0, result.Z + 8.0, groundZ)) {
            result.Z = groundZ;
        }

        if (world.PhysicsCorrectZ(result, groundZ)) {
            result.Z = groundZ;
        }

        return result;
    }

    protected function findSafeWalkTarget(out target : Vector) : bool {
        return findSafeTargetForActorInRange((CActor)thePlayer, minWalkDistance, maxWalkDistance, target);
    }

    protected function findSafeTargetForActorInRange(actor: CActor, minDistance: float, maxDistance: float, out target : Vector) : bool {
        var playerActor: CActor;
        var mac: CMovingAgentComponent;
        var world: CWorld;
        var candidate: Vector;
        var safeCandidate: Vector;
        var fallback: Vector;
        var hasFallback: bool;
        var i: int;

        playerActor = actor;
        if (!playerActor) {
            return false;
        }

        mac = playerActor.GetMovingAgentComponent();
        world = theGame.GetWorld();

        for (i = 0; i < walkTargetCandidates; i += 1) {
            candidate = randomGroundPosition(playerActor.GetWorldPosition(), minDistance, maxDistance);

            if (world.NavigationFindSafeSpot(candidate, walkSafeSpotPersonalSpace, walkSafeSpotSearchRadius, safeCandidate)) {
                candidate = safeCandidate;
            }

            if (mac && !mac.IsPositionValid(candidate)) {
                continue;
            }

            if (!hasFallback) {
                fallback = candidate;
                hasFallback = true;
            }

            if (mac && mac.CanGoStraightToDestination(candidate)) {
                target = candidate;
                return true;
            }

            if (world.NavigationLineTest(playerActor.GetWorldPosition(), candidate, walkSafeSpotPersonalSpace, false, true)) {
                target = candidate;
                return true;
            }
        }

        if (hasFallback) {
            target = fallback;
            return true;
        }

        return false;
    }

    protected function resetWalkTarget() {
        hasWalkTarget = false;
        lastWalkPosition = thePlayer.GetWorldPosition();
        lastWalkProgressAt = theGame.GetEngineTimeAsSeconds();
    }

    protected function isWalkTargetReached() : bool {
        if (!hasWalkTarget) {
            return true;
        }

        return VecDistance2D(thePlayer.GetWorldPosition(), currentWalkTarget) <= walkArrivalDistance;
    }

    protected function isWalkTargetTimedOut() : bool {
        if (!hasWalkTarget) {
            return true;
        }

        return theGame.GetEngineTimeAsSeconds() >= walkTargetIssuedAt + walkTargetTimeout;
    }

    protected function updateWalkProgress() {
        var currentPosition: Vector;

        if (!hasWalkTarget) {
            lastWalkPosition = thePlayer.GetWorldPosition();
            lastWalkProgressAt = theGame.GetEngineTimeAsSeconds();
            return;
        }

        currentPosition = thePlayer.GetWorldPosition();
        if (VecDistance2D(currentPosition, lastWalkPosition) >= walkStuckDistance) {
            lastWalkPosition = currentPosition;
            lastWalkProgressAt = theGame.GetEngineTimeAsSeconds();
        }
    }

    protected function isWalkTargetStuck() : bool {
        if (!hasWalkTarget) {
            return true;
        }

        return theGame.GetEngineTimeAsSeconds() >= lastWalkProgressAt + walkStuckTimeout;
    }

    protected function issueWalkMoveAsync() : bool {
        var playerActor: CActor;

        playerActor = (CActor)thePlayer;
        if (!playerActor) {
            return false;
        }

        if (!findSafeWalkTarget(currentWalkTarget)) {
            hasWalkTarget = false;
            log.error("failed to find safe walk target");
            return false;
        }

        if (issueScriptedMoveToPoint(playerActor, currentWalkTarget, walkSpeed, true)) {
            hasWalkTarget = true;
            walkTargetIssuedAt = theGame.GetEngineTimeAsSeconds();
            lastWalkPosition = thePlayer.GetWorldPosition();
            lastWalkProgressAt = walkTargetIssuedAt;
            log.debug("walk target issued: " + VecToString(currentWalkTarget));
        } else {
            hasWalkTarget = false;
            log.error("failed to issue walk target: " + VecToString(currentWalkTarget));
        }

        return hasWalkTarget;
    }

    protected function issueScriptedMoveToPoint(actor: CActor, target: Vector, speed: float, decoratePlayer: bool) : bool {
        return issueScriptedMoveToPointEx(actor, target, speed, decoratePlayer, 1, walkTargetTimeout, walkArrivalDistance, true);
    }

    protected function issueScriptedMoveToPointEx(
        actor: CActor,
        target: Vector,
        speed: float,
        decoratePlayer: bool,
        iterations: int,
        timeout: float,
        arrivalDistance: float,
        interruptOnInput: bool
    ) : bool {
        var aiTree: CAIMoveToPoint;
        var decorator: CAIPlayerActionDecorator;
        var heading: Vector;

        if (!actor) {
            return false;
        }

        actor.ActionCancelAll();

        aiTree = new CAIMoveToPoint in actor;
        aiTree.OnCreated();
        aiTree.enterExplorationOnStart = false;
        aiTree.params.moveSpeed = speed;
        aiTree.params.destinationPosition = target;

        heading = target - actor.GetWorldPosition();
        heading.Z = 0.0f;
        if (VecLength(heading) > 0.1f) {
            aiTree.params.destinationHeading = VecHeading(heading);
        } else {
            aiTree.params.destinationHeading = VecHeading(actor.GetHeadingVector());
        }

        aiTree.params.maxDistance = arrivalDistance;
        aiTree.params.maxIterationsNumber = iterations;
        aiTree.params.useTimeout = true;
        aiTree.params.timeoutValue = timeout;

        if (speed >= 2.0f) {
            aiTree.params.moveType = MT_Sprint;
        } else if (speed >= 1.0f) {
            aiTree.params.moveType = MT_FastRun;
        } else {
            aiTree.params.moveType = MT_Walk;
        }

        if (decoratePlayer) {
            thePlayer.GetMovingAgentComponent().SetGameplayMoveDirection(aiTree.params.destinationHeading);

            decorator = new CAIPlayerActionDecorator in actor;
            decorator.OnCreated();
            decorator.interruptOnInput = interruptOnInput;
            decorator.scriptedAction = aiTree;

            if (decorator) {
                actor.ForceAIBehavior(decorator, BTAP_Emergency);
            } else {
                actor.ForceAIBehavior(aiTree, BTAP_Emergency);
            }
        } else {
            actor.ForceAIBehavior(aiTree, BTAP_Emergency);
        }

        return true;
    }

    protected latent function moveActorRandom(
        actor: CActor,
        minDistance: float,
        maxDistance: float,
        moveType: EMoveType,
        absSpeed: float
    ) : bool {
        var whereTo: Vector;
        var mac: CMovingAgentComponent;
        var corrected: Vector;
        var result: bool;

        if (!actor) {
            return false;
        }

        whereTo = randomGroundPosition(actor.GetWorldPosition(), minDistance, maxDistance);

        mac = actor.GetMovingAgentComponent();
        if (mac && !mac.IsPositionValid(whereTo)) {
            if (mac.GetEndOfLineNavMeshPosition(whereTo, corrected)) {
                whereTo = corrected;
            }
        }

        result = actor.ActionMoveTo(whereTo, moveType, absSpeed, 1.5);
        return result;
    }

    event OnToggleWalkWander(action: SInputAction) {
        if (IsPressed(action)) {
            if (GetCurrentStateName() == 'AutoDriver_WalkWander') {
                stopCurrentAction();
                GotoState('AutoDriver_Idle');
                notify("AutoDriver walk wander stopped");
            } else {
                stopCurrentAction();
                GotoState('AutoDriver_WalkWander');
            }
        }
    }

    event OnToggleHorseRide(action: SInputAction) {
        if (IsPressed(action)) {
            if (GetCurrentStateName() == 'AutoDriver_HorseToggle'
                || GetCurrentStateName() == 'AutoDriver_OfficialTeleport'
                || GetCurrentStateName() == 'AutoDriver_RandomXYTeleport') {
                notify("AutoDriver horse/teleport transition is already running");
            } else {
                stopCurrentAction();
                GotoState('AutoDriver_HorseToggle');
            }
        }
    }

    event OnToggleHorseWander(action: SInputAction) {
        if (IsPressed(action)) {
            if (GetCurrentStateName() == 'AutoDriver_HorseWander') {
                stopCurrentAction();
                GotoState('AutoDriver_Idle');
                notify("AutoDriver horse wander stopped");
            } else {
                stopCurrentAction();
                GotoState('AutoDriver_HorseWander');
            }
        }
    }

    event OnToggleGodMode(action: SInputAction) {
        if (IsPressed(action)) {
            if (godModeEnabled) {
                disableGodMode();
            } else {
                enableGodMode();
            }
        }
    }

    event OnOfficialTeleport(action: SInputAction) {
        if (IsPressed(action)) {
            if (GetCurrentStateName() == 'AutoDriver_HorseToggle'
                || GetCurrentStateName() == 'AutoDriver_OfficialTeleport'
                || GetCurrentStateName() == 'AutoDriver_RandomXYTeleport') {
                notify("AutoDriver horse/teleport transition is already running");
            } else {
                stopAutoDriverActivityForTeleport();
                GotoState('AutoDriver_OfficialTeleport');
            }
        }
    }

    event OnRandomXYTeleport(action: SInputAction) {
        if (IsPressed(action)) {
            if (GetCurrentStateName() == 'AutoDriver_HorseToggle'
                || GetCurrentStateName() == 'AutoDriver_OfficialTeleport'
                || GetCurrentStateName() == 'AutoDriver_RandomXYTeleport') {
                notify("AutoDriver horse/teleport transition is already running");
            } else {
                stopAutoDriverActivityForTeleport();
                GotoState('AutoDriver_RandomXYTeleport');
            }
        }
    }
}

state AutoDriver_Idle in CModAutoDriver {
}

state AutoDriver_HorseToggle in CModAutoDriver {
    event OnEnterState(prevStateName: CName) {
        super.OnEnterState(prevStateName);
        HorseToggleLoop();
    }

    entry function HorseToggleLoop() {
        parent.performHorseToggle();
        parent.GotoState('AutoDriver_Idle');
    }
}

state AutoDriver_OfficialTeleport in CModAutoDriver {
    event OnEnterState(prevStateName: CName) {
        super.OnEnterState(prevStateName);
        OfficialTeleportLoop();
    }

    entry function OfficialTeleportLoop() {
        var reason: String;
        var ready: bool;
        var teleported: bool;

        ready = parent.prepareTeleportForTravel(reason);
        if (ready) {
            teleported = parent.performOfficialTeleport();
        } else {
            parent.notify("AutoDriver teleport blocked: " + reason);
        }
        parent.GotoState('AutoDriver_Idle');
    }
}

state AutoDriver_WalkWander in CModAutoDriver {
    event OnEnterState(prevStateName: CName) {
        super.OnEnterState(prevStateName);
        parent.resetWalkTarget();
        parent.notify("AutoDriver walk wander started");
        WalkLoop();
    }

    event OnLeaveState(nextStateName: CName) {
        parent.stopCurrentAction();
        super.OnLeaveState(nextStateName);
    }

    entry function WalkLoop() {
        while (parent.GetCurrentStateName() == 'AutoDriver_WalkWander') {
            if (thePlayer.IsUsingHorse(true)) {
                parent.notify("AutoDriver walk wander requires dismounted player");
                parent.GotoState('AutoDriver_Idle');
                return;
            }

            parent.updateWalkProgress();

            if (parent.isWalkTargetReached() || parent.isWalkTargetTimedOut() || parent.isWalkTargetStuck()) {
                parent.issueWalkMoveAsync();
            }

            Sleep(parent.walkTickInterval);
        }
    }
}

state AutoDriver_RandomXYTeleport in CModAutoDriver {
    event OnEnterState(prevStateName: CName) {
        super.OnEnterState(prevStateName);
        RandomXYTeleportLoop();
    }

    event OnLeaveState(nextStateName: CName) {
        super.OnLeaveState(nextStateName);
    }

    entry function RandomXYTeleportLoop() {
        parent.performRandomXYTeleport();
        parent.GotoState('AutoDriver_Idle');
    }
}

state AutoDriver_HorseWander in CModAutoDriver {
    event OnEnterState(prevStateName: CName) {
        super.OnEnterState(prevStateName);
        parent.notify("AutoDriver horse wander started");
        HorseLoop();
    }

    event OnLeaveState(nextStateName: CName) {
        parent.stopCurrentAction();
        super.OnLeaveState(nextStateName);
    }

    entry function HorseLoop() {
        var horse: CActor;

        while (parent.GetCurrentStateName() == 'AutoDriver_HorseWander') {
            if (!thePlayer.IsUsingHorse(true)) {
                parent.notify("AutoDriver horse wander requires mounted player");
                parent.GotoState('AutoDriver_Idle');
                return;
            }

            horse = (CActor)thePlayer.GetUsedVehicle();
            if (!horse) {
                parent.notify("AutoDriver could not find current horse actor");
                parent.GotoState('AutoDriver_Idle');
                return;
            }

            parent.moveActorRandom(horse, parent.minHorseDistance, parent.maxHorseDistance, MT_Run, parent.horseSpeed);
            Sleep(0.5);
        }
    }
}

function createAutoDriver() : CMod {
    return new CModAutoDriver in thePlayer;
}
// ----------------------------------------------------------------------------
