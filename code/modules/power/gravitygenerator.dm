//
// Gravity Generator
//

GLOBAL_LIST_EMPTY(gravity_generators) // We will keep track of this by adding new gravity generators to the list, and keying it with the z level.

#define POWER_IDLE 0
#define POWER_UP 1
#define POWER_DOWN 2

#define GRAV_NEEDS_SCREWDRIVER 0
#define GRAV_NEEDS_WELDING 1
#define GRAV_NEEDS_PLASTEEL 2
#define GRAV_NEEDS_WRENCH 3

//
// Abstract Generator
//

/obj/machinery/gravity_generator
	name = "gravitational generator"
	desc = "A device which produces a graviton field when set up."
	icon = 'icons/obj/machines/gravity_generator.dmi'
	density = TRUE
	move_resist = INFINITY
	use_power = NO_POWER_USE
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF
	var/sprite_number = 0

/obj/machinery/gravity_generator/safe_throw_at(atom/target, range, speed, mob/thrower, spin = TRUE, diagonals_first = FALSE, datum/callback/callback, force = MOVE_FORCE_STRONG, quickstart = TRUE)
	return FALSE

/obj/machinery/gravity_generator/ex_act(severity, target)
	if(severity == 1) // Very sturdy.
		set_broken()

/obj/machinery/gravity_generator/blob_act(obj/structure/blob/B)
	if(prob(20))
		set_broken()

/obj/machinery/gravity_generator/tesla_act(source, power, zap_range, tesla_flags, list/shocked_targets)
	. = ..()
	if(tesla_flags & TESLA_MACHINE_EXPLOSIVE)
		set_broken()
		ADD_TRAIT(src, TRAIT_TESLA_IGNORE, INNATE_TRAIT) // stops it from exploding over and over

/obj/machinery/gravity_generator/update_icon_state()
	. = ..()
	icon_state = "[get_status()]_[sprite_number]"

/obj/machinery/gravity_generator/proc/get_status()
	return "off"

// You aren't allowed to move.
/obj/machinery/gravity_generator/Move()
	. = ..()
	qdel(src)

/obj/machinery/gravity_generator/proc/set_broken()
	atom_break()

/obj/machinery/gravity_generator/proc/set_fix()
	stat &= ~BROKEN

/obj/machinery/gravity_generator/part/Destroy()
	if(main_part)
		qdel(main_part)
	set_broken()
	return ..()

//
// Part generator which is mostly there for looks
//

/obj/machinery/gravity_generator/part
	var/obj/machinery/gravity_generator/main/main_part

/obj/machinery/gravity_generator/part/Destroy()
	atom_break()
	if(main_part)
		UnregisterSignal(main_part, COMSIG_ATOM_UPDATED_ICON)
		main_part = null
	return ..()

/obj/machinery/gravity_generator/part/attackby(obj/item/I, mob/user, params)
	return main_part.attackby(I, user)

/obj/machinery/gravity_generator/part/get_status()
	if(!main_part)
		return
	return main_part.get_status()

/obj/machinery/gravity_generator/part/attack_hand(mob/user)
	return main_part.attack_hand(user)

/obj/machinery/gravity_generator/part/set_broken()
	..()
	if(!main_part || (main_part.stat & BROKEN))
		return
	main_part.set_broken()

/// Used to eat args
/obj/machinery/gravity_generator/part/proc/on_update_icon(obj/machinery/gravity_generator/source, updates, updated)
	SIGNAL_HANDLER
	return update_appearance(updates)

//
// Generator an admin can spawn
//
/obj/machinery/gravity_generator/main/station/admin
	use_power = NO_POWER_USE

/**
 * Main gravity generator
 *
 * The actual gravity generator, that actually holds the UI, contains the grav gen parts, ect.
 */
/obj/machinery/gravity_generator/main
	icon_state = "on_8"
	idle_power_usage = 0
	active_power_usage = 3000
	power_channel = AREA_USAGE_ENVIRON
	sprite_number = 8
	use_power = IDLE_POWER_USE
	interaction_flags_machine = INTERACT_MACHINE_ALLOW_SILICON | INTERACT_MACHINE_OFFLINE
	
	/// List of all gravity generator parts
	var/list/generator_parts = list()
	/// The gravity generator part in the very center, the fifth one, where we place the overlays.
	var/obj/machinery/gravity_generator/part/center_part
	
	/// Whether the gravity generator is currently active.
	var/on = TRUE
	/// If the main breaker is on/off, to enable/disable gravity.
	var/breaker = TRUE
	/// If the generatir os idle, charging, or down.
	var/charging_state = POWER_IDLE
	/// How much charge the gravity generator has, goes down when breaker is shut, and shuts down at 0.
	var/charge_count = 100

	/// The gravity overlay currently used.
	var/current_overlay = null
	/// When broken, what stage it is at (GRAV_NEEDS_SCREWDRIVER:0) (GRAV_NEEDS_WELDING:1) (GRAV_NEEDS_PLASTEEL:2) (GRAV_NEEDS_WRENCH:3)
	var/broken_state = GRAV_NEEDS_SCREWDRIVER
	/// Gravity value when on, honestly I don't know why it does it like this, but it does.
	var/setting = 1
	
	///Amount of shielding we offer against a radioactive nebula
	var/radioactive_nebula_shielding = 4

///Station generator that spawns with gravity turned off.
/obj/machinery/gravity_generator/main/off
	on = FALSE
	breaker = FALSE
	charge_count = 0

/obj/machinery/gravity_generator/main/station/Initialize(mapload)
	. = ..()
	setup_parts()
	if(on)
		center_part.add_overlay("activated")
	update_list()

/obj/machinery/gravity_generator/main/Destroy() // If we somehow get deleted, remove all of our other parts.
	investigate_log("was destroyed!", INVESTIGATE_GRAVITY)
	on = FALSE
	update_list()
	QDEL_NULL(center_part)
	QDEL_LIST(generator_parts)
	return ..()

/obj/machinery/gravity_generator/main/proc/setup_parts()
	var/turf/our_turf = get_turf(src)
	// 9x9 block obtained from the bottom center_part of the block
	var/list/spawn_turfs = block(locate(our_turf.x - 1, our_turf.y + 2, our_turf.z), locate(our_turf.x + 1, our_turf.y, our_turf.z))
	var/count = 10
	for(var/turf/T in spawn_turfs)
		count--
		if(T == our_turf) // Skip our turf.
			continue
		var/obj/machinery/gravity_generator/part/part = new(T)
		if(count == 5) // Middle
			center_part = part
		if(count <= 3) // Their sprite is the top part of the generator
			part.density = FALSE
			part.layer = WALL_OBJ_LAYER
		part.sprite_number = count
		part.main_part = src
		generator_parts += part
		part.update_appearance()
		part.RegisterSignal(src, COMSIG_ATOM_UPDATED_ICON, TYPE_PROC_REF(/obj/machinery/gravity_generator/part, on_update_icon))

/obj/machinery/gravity_generator/main/proc/connected_parts()
	return generator_parts.len == 8

/obj/machinery/gravity_generator/main/set_broken()
	..()
	for(var/obj/machinery/gravity_generator/internal_parts in generator_parts)
		if(!(internal_parts.stat & BROKEN))
			internal_parts.set_broken()
	center_part.cut_overlays()
	charge_count = 0
	breaker = 0
	set_power()
	disable()
	investigate_log("has broken down.", INVESTIGATE_GRAVITY)

/obj/machinery/gravity_generator/main/set_fix()
	..()
	for(var/obj/machinery/gravity_generator/internal_parts as anything in generator_parts)
		if(internal_parts.stat & BROKEN)
			internal_parts.set_fix()
	broken_state = FALSE
	update_appearance()
	set_power()

// Interaction

// Fixing the gravity generator.
/obj/machinery/gravity_generator/main/attackby(obj/item/I, mob/user, params)
	switch(broken_state)
		if(GRAV_NEEDS_SCREWDRIVER)
			if(I.tool_behaviour == TOOL_SCREWDRIVER)
				to_chat(user, span_notice("You secure the screws of the framework."))
				I.play_tool_sound(src)
				broken_state++
				update_appearance()
				return
		if(GRAV_NEEDS_WELDING)
			if(I.tool_behaviour == TOOL_WELDER)
				if(I.use_tool(src, user, 0, volume=50, amount=1))
					to_chat(user, span_notice("You mend the damaged framework."))
					broken_state++
					update_appearance()
				return
		if(GRAV_NEEDS_PLASTEEL)
			if(istype(I, /obj/item/stack/sheet/plasteel))
				var/obj/item/stack/sheet/plasteel/PS = I
				if(PS.get_amount() >= 10)
					PS.use(10)
					to_chat(user, span_notice("You add the plating to the framework."))
					playsound(src.loc, 'sound/machines/click.ogg', 75, 1)
					broken_state++
					update_appearance()
				else
					to_chat(user, span_warning("You need 10 sheets of plasteel!"))
				return
		if(GRAV_NEEDS_WRENCH)
			if(I.tool_behaviour == TOOL_WRENCH)
				to_chat(user, span_notice("You secure the plating to the framework."))
				I.play_tool_sound(src)
				set_fix()
				return
	return ..()

/obj/machinery/gravity_generator/main/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "GravityGenerator", name)
		ui.open()

/obj/machinery/gravity_generator/main/ui_data(mob/user)
	var/list/data = list()

	data["breaker"] = breaker
	data["charge_count"] = charge_count
	data["charging_state"] = charging_state
	data["on"] = on
	data["operational"] = (stat & BROKEN) ? FALSE : TRUE
	return data

/obj/machinery/gravity_generator/main/ui_act(action, params)

	if(..())
		return

	switch(action)
		if("gentoggle")
			breaker = !breaker
			investigate_log("was toggled [breaker ? "<font color='green'>ON</font>" : "<font color='red'>OFF</font>"] by [key_name(usr)].", INVESTIGATE_GRAVITY)
			set_power()
			. = TRUE

// Power and Icon States

/obj/machinery/gravity_generator/main/power_change()
	. = ..()
	investigate_log("has [stat & NOPOWER ? "lost" : "regained"] power.", INVESTIGATE_GRAVITY)
	set_power()

/obj/machinery/gravity_generator/main/get_status()
	if(stat & BROKEN)
		return "fix[min(broken_state, 3)]"
	return on || charging_state != POWER_IDLE ? "on" : "off"

/obj/machinery/gravity_generator/main/update_icon(updates=ALL)
	. = ..()
	for(var/obj/O in generator_parts)
		O.update_appearance()

// Set the charging state based on power/breaker.
/obj/machinery/gravity_generator/main/proc/set_power()
	var/new_state = FALSE
	if(stat & (NOPOWER|BROKEN) || !breaker)
		new_state = FALSE
	else if(breaker)
		new_state = TRUE

	charging_state = new_state ? POWER_UP : POWER_DOWN // Startup sequence animation.
	investigate_log("is now [charging_state == POWER_UP ? "charging" : "discharging"].", INVESTIGATE_GRAVITY)
	update_appearance()

// Set the state of the gravity.
/obj/machinery/gravity_generator/main/proc/set_state(new_state)
	charging_state = POWER_IDLE
	on = new_state
	use_power = on ? ACTIVE_POWER_USE : IDLE_POWER_USE
	// Sound the alert if gravity was just enabled or disabled.
	var/alert = FALSE
	if(SSticker.IsRoundInProgress())
		if(on) // If we turned on and the game is live.
			if(gravity_in_level() == 0)
				alert = 1
				investigate_log("was brought online and is now producing gravity for this level.", INVESTIGATE_GRAVITY)
				message_admins("The gravity generator was brought online [ADMIN_VERBOSEJMP(src)]")
		else
			if(gravity_in_level() == 1)
				alert = 1
				investigate_log("was brought offline and there is now no gravity for this level.", INVESTIGATE_GRAVITY)
				message_admins("The gravity generator was brought offline with no backup generator. [ADMIN_VERBOSEJMP(src)]")

	if(alert)
		complete_state_update()
		shake_everyone()
	src.updateUsrDialog()

/obj/machinery/gravity_generator/main/proc/enable()
	charging_state = POWER_IDLE
	on = TRUE
	use_power = ACTIVE_POWER_USE

	var/old_gravity = gravity_in_level()
	complete_state_update()

	if (!old_gravity)
		if(SSticker.current_state == GAME_STATE_PLAYING)
			investigate_log("was brought online and is now producing gravity for this level.", INVESTIGATE_GRAVITY)
			message_admins("The gravity generator was brought online [ADMIN_VERBOSEJMP(src)]")
		shake_everyone()


/obj/machinery/gravity_generator/main/proc/disable()
	charging_state = POWER_IDLE
	on = FALSE
	use_power = IDLE_POWER_USE

	var/old_gravity = gravity_in_level()
	complete_state_update()

	if (old_gravity)
		if(SSticker.current_state == GAME_STATE_PLAYING)
			investigate_log("was brought offline and there is now no gravity for this level.", INVESTIGATE_GRAVITY)
			message_admins("The gravity generator was brought offline with no backup generator. [ADMIN_VERBOSEJMP(src)]")
		shake_everyone()

/obj/machinery/gravity_generator/main/proc/complete_state_update()
	update_appearance()
	update_list()

// Charge/Discharge and turn on/off gravity when you reach 0/100 percent.
// Also emit radiation and handle the overlays.
/obj/machinery/gravity_generator/main/process()
	if(stat & BROKEN)
		return
	if(charging_state == POWER_IDLE)
		return
	if(charging_state == POWER_UP && charge_count >= 100)
		enable()
	else if(charging_state == POWER_DOWN && charge_count <= 0)
		disable()
	else
		if(charging_state == POWER_UP)
			charge_count += 2
		else if(charging_state == POWER_DOWN)
			charge_count -= 2

		if(charge_count % 4 == 0 && prob(75)) // Let them know it is charging/discharging.
			playsound(src.loc, 'sound/effects/empulse.ogg', 100, 1)

		updateDialog()
		if(prob(25)) // To help stop "Your clothes feel warm." spam.
			pulse_radiation()

		var/overlay_state = null
		switch(charge_count)
			if(0 to 20)
				overlay_state = null
			if(21 to 40)
				overlay_state = "startup"
			if(41 to 60)
				overlay_state = "idle"
			if(61 to 80)
				overlay_state = "activating"
			if(81 to 100)
				overlay_state = "activated"

		if(overlay_state != current_overlay)
			if(center_part)
				center_part.cut_overlays()
				if(overlay_state)
					center_part.add_overlay(overlay_state)
				current_overlay = overlay_state


/obj/machinery/gravity_generator/main/proc/pulse_radiation()
	radiation_pulse(src, 200)

// Shake everyone on the z level to let them know that gravity was enagaged/disenagaged.
/obj/machinery/gravity_generator/main/proc/shake_everyone()
	var/turf/T = get_turf(src)
	var/sound/alert_sound = sound('sound/effects/alert.ogg')
	for(var/i in GLOB.mob_list)
		var/mob/M = i
		if(M.z != z)
			continue
		M.update_gravity(M.mob_has_gravity())
		if(M.client)
			shake_camera(M, 15, 1)
			M.playsound_local(T, null, 100, 1, 0.5, S = alert_sound)

/obj/machinery/gravity_generator/main/proc/gravity_in_level()
	var/turf/T = get_turf(src)
	if(!T)
		return FALSE
	if(GLOB.gravity_generators["[T.z]"])
		return length(GLOB.gravity_generators["[T.z]"])
	return FALSE

/obj/machinery/gravity_generator/main/proc/update_list()
	var/turf/T = get_turf(src)
	if(!T)
		return
	var/list/z_list = list()
	// Multi-Z, station gravity generator generates gravity on all ZTRAIT_STATION z-levels.
	if(SSmapping.level_trait(T.z, ZTRAIT_STATION))
		for(var/z in SSmapping.levels_by_trait(ZTRAIT_STATION))
			z_list += z
	else
		z_list += T.z
	for(var/z in z_list)
		if(!GLOB.gravity_generators["[z]"])
			GLOB.gravity_generators["[z]"] = list()
		if(on)
			GLOB.gravity_generators["[z]"] |= src
		else
			GLOB.gravity_generators["[z]"] -= src
		SSmapping.calculate_z_level_gravity(z)

/obj/machinery/gravity_generator/main/proc/change_setting(value)
	if(value != setting)
		setting = value
		shake_everyone()

/obj/machinery/gravity_generator/main/CtrlClick(mob/user)
	if(!user.canUseTopic(src, !issilicon(user)))
		return FALSE
	breaker = !breaker
	investigate_log("was toggled [breaker ? "<font color='green'>ON</font>" : "<font color='red'>OFF</font>"] by [key_name(usr)].", INVESTIGATE_GRAVITY)
	set_power()
	return TRUE


/obj/machinery/gravity_generator/main/proc/blackout()
	charge_count = 0
	breaker = FALSE
	set_power()
	disable()
	investigate_log("was turned off by blackout event or a gravity anomaly detonation.", INVESTIGATE_GRAVITY)

// Misc

/obj/item/paper/guides/jobs/engi/gravity_gen
	name = "paper- 'Generate your own gravity!'"
	info = {"<h1>Gravity Generator Instructions For Dummies</h1>
	<p>Surprisingly, gravity isn't that hard to make! All you have to do is inject deadly radioactive minerals into a ball of
	energy and you have yourself gravity! You can turn the machine on or off when required but you must remember that the generator
	will EMIT RADIATION when charging or discharging, you can tell it is charging or discharging by the noise it makes, so please WEAR PROTECTIVE CLOTHING.</p>
	<br>
	<h3>It blew up!</h3>
	<p>Don't panic! The gravity generator was designed to be easily repaired. If, somehow, the sturdy framework did not survive then
	please proceed to panic; otherwise follow these steps.</p><ol>
	<li>Secure the screws of the framework with a screwdriver.</li>
	<li>Mend the damaged framework with a welding tool.</li>
	<li>Add additional plasteel plating.</li>
	<li>Secure the additional plating with a wrench.</li></ol>"}
