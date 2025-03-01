///Can the atom pass this mob (always true for /mob)
/**
  * Get the current movespeed delay of the mob
  *
  * DO NOT OVERRIDE THIS UNLESS YOU ABSOLUTELY HAVE TO.
  * THIS IS BEING PHASED OUT FOR THE MOVESPEED MODIFICATION SYSTEM.
  * See mob_movespeed.dm
  */
/mob/proc/movement_delay()	//update /living/movement_delay() if you change this
	return cached_multiplicative_slowdown

/**
  * If your mob is conscious, drop the item in the active hand
  *
  * This is a hidden verb, likely for binding with winset for hotkeys
  */
/client/verb/drop_item()
	set hidden = TRUE
	if(!iscyborg(mob) && mob.stat == CONSCIOUS)
		mob.dropItemToGround(mob.get_active_held_item())
	return

/**
  * force move the control_object of your client mob
  *
  * Used in admin possession and called from the client Move proc
  * ensures the possessed object moves and not the admin mob
  *
  * Has no sanity other than checking density
  */
/client/proc/Move_object(direct)
	if(mob && mob.control_object)
		if(mob.control_object.density)
			step(mob.control_object,direct)
			if(!mob.control_object)
				return
			mob.control_object.setDir(direct)
		else
			mob.control_object.forceMove(get_step(mob.control_object,direct))

#define MOVEMENT_DELAY_BUFFER 0.75
#define MOVEMENT_DELAY_BUFFER_DELTA 1.25

/**
  * Move a client in a direction
  *
  * Huge proc, has a lot of functionality
  *
  * Mostly it will despatch to the mob that you are the owner of to actually move
  * in the physical realm
  *
  * Things that stop you moving as a mob:
  * * world time being less than your next move_delay
  * * not being in a mob, or that mob not having a loc
  * * missing the n and direction parameters
  * * being in remote control of an object (calls Moveobject instead)
  * * being dead (it ghosts you instead)
  *
  * Things that stop you moving as a mob living (why even have OO if you're just shoving it all
  * in the parent proc with istype checks right?):
  * * having incorporeal_move set (calls Process_Incorpmove() instead)
  * * being grabbed
  * * being buckled  (relaymove() is called to the buckled atom instead)
  * * having your loc be some other mob (relaymove() is called on that mob instead)
  * * Not having MOBILITY_MOVE
  * * Failing Process_Spacemove() call
  *
  * At this point, if the mob is is confused, then a random direction and target turf will be calculated for you to travel to instead
  *
  * Now the parent call is made (to the byond builtin move), which moves you
  *
  * Some final move delay calculations (doubling if you moved diagonally successfully)
  *
  * if mob throwing is set I believe it's unset at this point via a call to finalize
  *
  * Finally if you're pulling an object and it's dense, you are turned 180 after the move
  * (if you ask me, this should be at the top of the move so you don't dance around)
  *
  */
/client/Move(n, direct)
	if(world.time < move_delay) //do not move anything ahead of this check please
		return FALSE
	else
		next_move_dir_add = 0
		next_move_dir_sub = 0
	var/old_move_delay = move_delay
	move_delay = world.time + world.tick_lag //this is here because Move() can now be called mutiple times per tick
	if(!mob || !mob.loc)
		return FALSE
	if(!n || !direct)
		return FALSE
	if(mob.notransform)
		return FALSE	//This is sota the goto stop mobs from moving var
	if(mob.control_object)
		return Move_object(direct)
	if(mob.stat == DEAD && (SSlag_switch.measures[DISABLE_DEAD_KEYLOOP] && !is_admin(mob)))
		return FALSE
	if(!isliving(mob))
		return mob.Move(n, direct)
	if(mob.stat == DEAD)
		mob.ghostize()
		return FALSE
	if(mob.force_moving)
		return FALSE

	var/mob/living/L = mob  //Already checked for isliving earlier
	/*if(L.incorporeal_move)	//Move though walls //yogs start - turned into component
		Process_Incorpmove(direct)
		return FALSE*/ //yogs end

	if(mob.remote_control)					//we're controlling something, our movement is relayed to it
		return mob.remote_control.relaymove(mob, direct)

	if(isAI(mob))
		return AIMove(direct,mob)

	if(Process_Grab()) //are we restrained by someone's grip?
		return

	if(mob.buckled)							//if we're buckled to something, tell it we moved.
		return mob.buckled.relaymove(mob, direct)

	if(!(L.mobility_flags & MOBILITY_MOVE))
		return FALSE

	if(ismovable(mob.loc))	//Inside an object, tell it we moved
		var/atom/loc_atom = mob.loc
		return loc_atom.relaymove(mob, direct)

	if(!mob.Process_Spacemove(direct))
		return FALSE

	var/handled = SEND_SIGNAL(L, COMSIG_MOB_CLIENT_PRE_MOVE, direct)
	if(handled)
		return FALSE//yogs end

	//We are now going to move
	var/add_delay = mob.movement_delay()
	mob.set_glide_size(DELAY_TO_GLIDE_SIZE(add_delay * (((direct & 3) && (direct & 12)) ? 2 : 1))) // set it now in case of pulled objects
	if(old_move_delay + (add_delay*MOVEMENT_DELAY_BUFFER_DELTA) + MOVEMENT_DELAY_BUFFER > world.time)
		move_delay = old_move_delay
	else
		move_delay = world.time

	//this is in two areas, i have no clue why, all i know is that i hate it and don't have the time to fix it
	if(L.has_status_effect(/datum/status_effect/confusion))
		var/newdir = 0
		if(prob(50))
			newdir = angle2dir(dir2angle(direct) + pick(45, -45))
		else if(prob(50) && L.get_timed_status_effect_duration(/datum/status_effect/confusion) > 10 SECONDS)
			newdir = angle2dir(dir2angle(direct) + pick(90, -90))
		if(newdir)
			direct = newdir
			n = get_step(L, direct)

	. = ..()

	var/diagonal = (direct & (direct - 1)) && mob.loc == n
	if(diagonal) //moved diagonally successfully
		add_delay *= SQRT_2 // sqrt(2)
	mob.set_glide_size(DELAY_TO_GLIDE_SIZE(add_delay))
	move_delay += add_delay
	if(.) // If mob is null here, we deserve the runtime
		if(mob.throwing)
			mob.throwing.finalize(FALSE)

	var/atom/movable/P = mob.pulling
	if(P && !ismob(P) && P.density)
		mob.setDir(turn(mob.dir, 180))

	SEND_SIGNAL(L, COMSIG_MOB_CLIENT_MOVED)
/**
  * Checks to see if you're being grabbed and if so attempts to break it
  *
  * Called by client/Move()
  */
/client/proc/Process_Grab()
	if(!mob.pulledby)
		return FALSE
	if(mob.pulledby == mob.pulling && mob.pulledby.grab_state == GRAB_PASSIVE) //Don't autoresist passive grabs if we're grabbing them too.
		return FALSE
	if(HAS_TRAIT(mob, TRAIT_INCAPACITATED))
		COOLDOWN_START(src, move_delay, 1 SECONDS)
		return TRUE
	else if(mob.restrained(ignore_grab = TRUE))
		COOLDOWN_START(src, move_delay, 1 SECONDS)
		to_chat(src, span_warning("You're restrained! You can't move!"))
		return TRUE
	return mob.resist_grab(TRUE)

/**
  * Allows mobs to ignore density and phase through objects
  *
  * Called by client/Move()
  *
  * The behaviour depends on the incorporeal_move value of the mob
  *
  * * INCORPOREAL_MOVE_BASIC - forceMoved to the next tile with no stop
  * * INCORPOREAL_MOVE_SHADOW  - the same but leaves a cool effect path
  * * INCORPOREAL_MOVE_JAUNT - the same but blocked by holy tiles
  *
  * You'll note this is another mob living level proc living at the client level
  */
/client/proc/Process_Incorpmove(direct)
	var/turf/mobloc = get_turf(mob)
	if(!isliving(mob))
		return
	var/mob/living/L = mob
	switch(L.incorporeal_move)
		if(INCORPOREAL_MOVE_BASIC)
			var/T = get_step(L,direct)
			if(T)
				L.forceMove(T)
			L.setDir(direct)
		if(INCORPOREAL_MOVE_SHADOW)
			if(prob(50))
				var/locx
				var/locy
				switch(direct)
					if(NORTH)
						locx = mobloc.x
						locy = (mobloc.y+2)
						if(locy>world.maxy)
							return
					if(SOUTH)
						locx = mobloc.x
						locy = (mobloc.y-2)
						if(locy<1)
							return
					if(EAST)
						locy = mobloc.y
						locx = (mobloc.x+2)
						if(locx>world.maxx)
							return
					if(WEST)
						locy = mobloc.y
						locx = (mobloc.x-2)
						if(locx<1)
							return
					else
						return
				var/target = locate(locx,locy,mobloc.z)
				if(target)
					L.loc = target
					var/limit = 2//For only two trailing shadows.
					for(var/turf/T in getline(mobloc, L.loc))
						new /obj/effect/temp_visual/dir_setting/ninja/shadow(T, L.dir)
						limit--
						if(limit<=0)
							break
			else
				new /obj/effect/temp_visual/dir_setting/ninja/shadow(mobloc, L.dir)
				var/T = get_step(L,direct)
				if(T)
					L.forceMove(T)
			L.setDir(direct)
		if(INCORPOREAL_MOVE_JAUNT) //Incorporeal move, but blocked by holy-watered tiles and salt piles.
			var/turf/open/floor/stepTurf = get_step(L, direct)
			if(stepTurf)
				for(var/obj/effect/decal/cleanable/food/salt/S in stepTurf)
					to_chat(L, span_warning("[S] bars your passage!"))
					if(isrevenant(L))
						var/mob/living/simple_animal/revenant/R = L
						R.reveal(20)
						R.stun(20)
					return
				if(stepTurf.turf_flags & NOJAUNT)
					to_chat(L, span_warning("Some strange aura is blocking the way."))
					return
				if (locate(/obj/effect/blessing, stepTurf))
					to_chat(L, span_warning("Holy energies block your path!"))
					return

				L.forceMove(stepTurf)
			L.setDir(direct)
	return TRUE


/**
  * Handles mob/living movement in space (or no gravity)
  *
  * Called by /client/Move()
  *
  * return TRUE for movement or FALSE for none
  *
  * You can move in space if you have a spacewalk ability
  */
/mob/Process_Spacemove(movement_dir = 0)
	if(spacewalk || ..())
		return TRUE
	var/atom/movable/backup = get_spacemove_backup()
	if(backup)
		if(istype(backup) && movement_dir && !backup.anchored)
			if(backup.newtonian_move(turn(movement_dir, 180))) //You're pushing off something movable, so it moves
				to_chat(src, span_info("You push off of [backup] to propel yourself."))
		return TRUE
	return FALSE

/**
  * Find movable atoms? near a mob that are viable for pushing off when moving
  */
/mob/get_spacemove_backup()
	for(var/A in orange(1, get_turf(src)))
		if(isarea(A))
			continue
		else if(isturf(A))
			var/turf/turf = A
			if(isspaceturf(turf))
				continue
			if(!turf.density && !mob_negates_gravity())
				continue
			return A
		else
			var/atom/movable/AM = A
			if(AM == buckled)
				continue
			if(ismob(AM))
				var/mob/M = AM
				if(M.buckled)
					continue
			if(!AM.CanPass(src) || AM.density)
				if(AM.anchored)
					return AM
				if(pulling == AM)
					continue
				. = AM

/**
  * Returns true if a mob has gravity
  *
  * I hate that this exists
  */
/mob/proc/mob_has_gravity()
	return has_gravity()

/**
  * Does this mob ignore gravity
  */
/mob/proc/mob_negates_gravity()
	return FALSE

/**
 * used for determining if a mob should be flung
 */
/mob/proc/mob_has_heavy_gravity()
	return FALSE

/// Called when this mob slips over, override as needed
/mob/proc/slip(knockdown_amount, obj/O, lube, stun, force_drop)
	return

/// Update the gravity status of this mob
/mob/proc/update_gravity()
	return

//bodypart selection verbs - Cyberboss
//8: repeated presses toggles through head - eyes - mouth
//9: eyes 8: head 7: mouth
//4: r-arm 5: chest 6: l-arm
//1: r-leg 2: groin 3: l-leg

///Validate the client's mob has a valid zone selected
/client/proc/check_has_body_select()
	return mob && mob.hud_used && mob.hud_used.zone_select && istype(mob.hud_used.zone_select, /atom/movable/screen/zone_sel)

/**
  * Hidden verb to set the target zone of a mob to the head
  *
  * (bound to 8) - repeated presses toggles through head - eyes - mouth
  */

///Hidden verb to target the head, bound to 8
/client/verb/body_toggle_head()
	set name = "body-toggle-head"
	set hidden = TRUE

	if(!check_has_body_select())
		return

	var/next_in_line
	switch(mob.zone_selected)
		if(BODY_ZONE_HEAD)
			next_in_line = BODY_ZONE_PRECISE_EYES
		if(BODY_ZONE_PRECISE_EYES)
			next_in_line = BODY_ZONE_PRECISE_MOUTH
		else
			next_in_line = BODY_ZONE_HEAD

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(next_in_line, mob)

///Hidden verb to target the eyes, bound to 7
/client/verb/body_eyes()
	set name = "body-eyes"
	set hidden = TRUE

	if(!check_has_body_select())
		return

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(BODY_ZONE_PRECISE_EYES, mob)


///Hidden verb to target the mouth, bound to 9
/client/verb/body_mouth()
	set name = "body-mouth"
	set hidden = TRUE

	if(!check_has_body_select())
		return

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(BODY_ZONE_PRECISE_MOUTH, mob)

///Hidden verb to target the right arm, bound to 4
/client/verb/body_r_arm()
	set name = "body-r-arm"
	set hidden = TRUE

	if(!check_has_body_select())
		return

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(BODY_ZONE_R_ARM, mob)

///Hidden verb to target the chest, bound to 5
/client/verb/body_chest()
	set name = "body-chest"
	set hidden = TRUE

	if(!check_has_body_select())
		return

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(BODY_ZONE_CHEST, mob)

///Hidden verb to target the left arm, bound to 6
/client/verb/body_l_arm()
	set name = "body-l-arm"
	set hidden = TRUE

	if(!check_has_body_select())
		return

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(BODY_ZONE_L_ARM, mob)

///Hidden verb to target the right leg, bound to 1
/client/verb/body_r_leg()
	set name = "body-r-leg"
	set hidden = TRUE

	if(!check_has_body_select())
		return

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(BODY_ZONE_R_LEG, mob)

///Hidden verb to target the groin, bound to 2
/client/verb/body_groin()
	set name = "body-groin"
	set hidden = TRUE

	if(!check_has_body_select())
		return

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(BODY_ZONE_PRECISE_GROIN, mob)

///Hidden verb to target the left leg, bound to 3
/client/verb/body_l_leg()
	set name = "body-l-leg"
	set hidden = TRUE

	if(!check_has_body_select())
		return

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(BODY_ZONE_L_LEG, mob)

///Verb to toggle the walk or run status
/client/verb/toggle_walk_run()
	set name = "toggle-walk-run"
	set hidden = TRUE
	set instant = TRUE
	if(mob)
		mob.toggle_move_intent(usr)

/**
  * Toggle the move intent of the mob
  *
  * triggers an update the move intent hud as well
  */
/mob/proc/toggle_move_intent(mob/user)
	if(m_intent == MOVE_INTENT_RUN)
		m_intent = MOVE_INTENT_WALK
	else
		m_intent = MOVE_INTENT_RUN
	if(hud_used && hud_used.static_inventory)
		for(var/atom/movable/screen/mov_intent/selector in hud_used.static_inventory)
			selector.update_appearance(UPDATE_ICON)

///Moves a mob upwards in z level
/mob/verb/up()
	set name = "Move Upwards"
	set category = "IC"

	if(remote_control)
		return remote_control.relaymove(src, UP)

	var/turf/current_turf = get_turf(src)
	var/turf/above_turf = GET_TURF_ABOVE(current_turf)

	if(!above_turf)
		to_chat(src, span_warning("There's nowhere to go in that direction!"))
		return

	if(ismovable(loc)) //Inside an object, tell it we moved
		var/atom/loc_atom = loc
		return loc_atom.relaymove(src, UP)

	var/ventcrawling_flag = HAS_TRAIT(src, TRAIT_MOVE_VENTCRAWLING) ? ZMOVE_VENTCRAWLING : 0

	if(can_z_move(DOWN, above_turf, current_turf, ZMOVE_FALL_FLAGS|ventcrawling_flag)) //Will we fall down if we go up?
		if(buckled)
			to_chat(src, span_warning("[buckled] is not capable of flight."))
		else
			to_chat(src, span_warning("You are not Superman."))
		return
	balloon_alert(src, "moving up...")
	var/move_time = isobserver(src) ? 0 : 1 SECONDS
	if(hud_used?.move_up && move_time)
		hud_used.move_up.icon_state = "move_up_using"
	if(do_after(src, move_time))
		if(zMove(UP, z_move_flags = ZMOVE_FLIGHT_FLAGS|ZMOVE_FEEDBACK|ventcrawling_flag))
			to_chat(src, span_notice("You move upwards."))
	if(hud_used?.move_up)
		hud_used.move_up.icon_state = initial(hud_used.move_up.icon_state)
	

///Moves a mob down a z level
/mob/verb/down()
	set name = "Move Down"
	set category = "IC"

	if(remote_control)
		return remote_control.relaymove(src, DOWN)

	var/turf/current_turf = get_turf(src)
	var/turf/below_turf = GET_TURF_BELOW(current_turf)
	
	if(!below_turf)
		to_chat(src, span_warning("There's nowhere to go in that direction!"))
		return

	if(ismovable(loc)) //Inside an object, tell it we moved
		var/atom/loc_atom = loc
		return loc_atom.relaymove(src, DOWN)

	var/ventcrawling_flag = HAS_TRAIT(src, TRAIT_MOVE_VENTCRAWLING) ? ZMOVE_VENTCRAWLING : 0
	balloon_alert(src, "moving down...")
	var/move_time = isobserver(src) ? 0 : 1 SECONDS
	if(hud_used?.move_down && move_time)
		hud_used.move_down.icon_state = "move_down_using"
	if(do_after(src, move_time))
		if(zMove(DOWN, z_move_flags = ZMOVE_FLIGHT_FLAGS|ZMOVE_FEEDBACK|ventcrawling_flag))
			to_chat(src, span_notice("You move down."))
	if(hud_used?.move_down)
		hud_used.move_down.icon_state = initial(hud_used.move_down.icon_state)

/mob/abstract_move(atom/destination)
	var/turf/new_turf = get_turf(destination)
	if(new_turf && (istype(new_turf, /turf/cordon/secret) || is_secret_level(new_turf.z)) && !client?.holder)
		return
	return ..()
