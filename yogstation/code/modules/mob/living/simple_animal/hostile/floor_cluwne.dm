GLOBAL_VAR_INIT(floor_cluwnes, 0)

#define STAGE_HAUNT 1
#define STAGE_SPOOK 2
#define STAGE_TORMENT 3
#define STAGE_ATTACK 4
#define MANIFEST_DELAY 9

/mob/living/simple_animal/hostile/floor_cluwne
	name = "???"
	desc = "...."
	icon = 'yogstation/icons/obj/clothing/masks.dmi'
	icon_state = "cluwne"
	icon_living = "cluwne"
	icon_gib = "clown_gib"
	maxHealth = 250
	health = 250
	speed = -1
	attacktext = "attacks"
	attack_sound = 'sound/items/bikehorn.ogg'
	del_on_death = TRUE
	pass_flags = PASSTABLE | PASSGRILLE | PASSMOB | LETPASSTHROW | PASSGLASS | PASSBLOB | PASSMACHINES //it's practically a ghost when unmanifested (under the floor)
	sentience_type = SENTIENCE_BOSS
	loot = list(/obj/item/clothing/mask/yogs/cluwne)
	wander = FALSE
	minimum_distance = 2
	move_to_delay = 1
	environment_smash = FALSE
	lose_patience_timeout = FALSE
	pixel_y = 8
	pressure_resistance = 200
	minbodytemp = 0
	maxbodytemp = 1500
	atmos_requirements = list("min_oxy" = 0, "max_oxy" = 0, "min_tox" = 0, "max_tox" = 0, "min_co2" = 0, "max_co2" = 0, "min_n2" = 0, "max_n2" = 0)
	var/mob/living/carbon/human/current_victim
	var/manifested = FALSE
	var/switch_stage = 60
	var/stage = STAGE_HAUNT
	var/interest = 0
	var/target_area
	var/invalid_area_typecache = list(/area/space, /area/lavaland, /area/mine, /area/centcom, /area/centcom/reebe, /area/shuttle/syndicate)
	var/eating = FALSE
	var/obj/effect/dummy/floorcluwne_orbit/poi
	var/obj/effect/temp_visual/fcluwne_manifest/cluwnehole
	move_resist = INFINITY
	hud_type = /datum/hud/ghost
	hud_possible = list(ANTAG_HUD)


/mob/living/simple_animal/hostile/floor_cluwne/Initialize(mapload)
	. = ..()
	access_card = new /obj/item/card/id(src)
	access_card.access = get_all_accesses()//THERE IS NO ESCAPE
	ADD_TRAIT(access_card, TRAIT_NODROP, ABSTRACT_ITEM_TRAIT)
	invalid_area_typecache = typecacheof(invalid_area_typecache)
	Manifest()
	if(!current_victim)
		Acquire_Victim()
	poi = new(src)

/mob/living/simple_animal/hostile/floor_cluwne/med_hud_set_health()
	return //we use a different hud

/mob/living/simple_animal/hostile/floor_cluwne/med_hud_set_status()
	return //we use a different hud

/mob/living/simple_animal/hostile/floor_cluwne/Destroy()
	QDEL_NULL(poi)
	return ..()


/mob/living/simple_animal/hostile/floor_cluwne/attack_hand(mob/living/carbon/human/M)
	..()
	playsound(src.loc, 'sound/items/bikehorn.ogg', 50, 1)


/mob/living/simple_animal/hostile/floor_cluwne/CanPass(atom/A, turf/target)
	SHOULD_CALL_PARENT(FALSE)
	return TRUE


/mob/living/simple_animal/hostile/floor_cluwne/Life(seconds_per_tick = SSMOBS_DT, times_fired)
	do_jitter_animation(1000)
	pixel_y = 8
	var/area/A = get_area(loc) // Has to be separated from the below since is_type_in_typecache is also a funky macro
	if(is_type_in_typecache(A, invalid_area_typecache) || !is_station_level(z))
		var/area = pick(GLOB.teleportlocs)
		var/area/tp = GLOB.teleportlocs[area]
		forceMove(pick(get_area_turfs(tp.type)))

	if(!current_victim)
		Acquire_Victim()

	if(stage && !manifested)
		On_Stage()

	if(stage == STAGE_ATTACK)
		playsound(src, 'yogstation/sound/misc/cluwne_breathing.ogg', 75, 1)

	if(eating)
		return

	var/turf/T = get_turf(current_victim)
	A = get_area(T) // Has to be separated from the below since is_type_in_typecache is also a funky macro
	if(prob(5))//checks roughly every 20 ticks
		if(current_victim.stat == DEAD || current_victim.dna.check_mutation(CLUWNEMUT) || is_type_in_typecache(A, invalid_area_typecache) || !is_station_level(current_victim.z))
			if(!Found_You())
				Acquire_Victim()

	if(get_dist(src, current_victim) > 9 && !manifested &&  !is_type_in_typecache(A, invalid_area_typecache))//if cluwne gets stuck he just teleports
		do_teleport(src, T)

	interest++
	if(interest >= switch_stage * 4)
		stage = STAGE_ATTACK

	else if(interest >= switch_stage * 2)
		stage = STAGE_TORMENT

	else if(interest >= switch_stage)
		stage = STAGE_SPOOK

	else if(interest < switch_stage)
		stage = STAGE_HAUNT

	..()

/mob/living/simple_animal/hostile/floor_cluwne/Goto(target, delay, minimum_distance)
	var/area/A = get_area(current_victim.loc)
	if(!manifested && !is_type_in_typecache(A, invalid_area_typecache) && is_station_level(current_victim.z))
		walk_to(src, target, minimum_distance, delay)
	else
		walk_to(src,0)

/mob/living/simple_animal/hostile/floor_cluwne/mob_negates_gravity()
	return TRUE

/mob/living/simple_animal/hostile/floor_cluwne/FindTarget()
	return current_victim


/mob/living/simple_animal/hostile/floor_cluwne/CanAttack(atom/the_target)//you will not escape
	return TRUE


/mob/living/simple_animal/hostile/floor_cluwne/AttackingTarget()
	return


/mob/living/simple_animal/hostile/floor_cluwne/LoseTarget()
	return


/mob/living/simple_animal/hostile/floor_cluwne/electrocute_act(shock_damage, obj/source, siemens_coeff = 1, zone = null, override = FALSE, tesla_shock = FALSE, illusion = FALSE, stun = TRUE)//prevents runtimes with machine fuckery
	return FALSE

/mob/living/simple_animal/hostile/floor_cluwne/proc/Found_You()
	var/foundVictim = FALSE
	
	for(var/obj/structure/closet/hiding_spot in orange(7,src))
		if(current_victim.loc == hiding_spot)
			hiding_spot.bust_open()
			to_chat(current_victim, span_warning("...edih t'nac uoY"))
			foundVictim = TRUE
	
	for(var/obj/mecha/hiding_spot in orange(7,src))
		if(hiding_spot.occupant == current_victim)
			hiding_spot.go_out(TRUE)
			to_chat(current_victim, span_warning("...thgif t'nac uoY"))
			foundVictim = TRUE

	for(var/obj/structure/bed/roller/cheap_escape in orange(7,src))
		if(cheap_escape.buckled_mobs.Find(current_victim))
			cheap_escape.unbuckle_mob(current_victim, TRUE)
			to_chat(current_victim, span_warning("...epacse t'nac uoY"))
			foundVictim = TRUE

	if(foundVictim)
		current_victim.Paralyze(40)

	return foundVictim

/mob/living/simple_animal/hostile/floor_cluwne/proc/Acquire_Victim(specific)
	for(var/I in GLOB.player_list)//better than a potential recursive loop
		var/mob/living/carbon/human/H = pick(GLOB.player_list)//so the check is fair
		var/area/A
		if(specific)
			H = specific
			A = get_area(H.loc)
			if(H.stat != DEAD && H.has_dna() && !H.dna.check_mutation(CLUWNEMUT) && !is_type_in_typecache(A, invalid_area_typecache) && is_station_level(H.z))
				return target = current_victim

		A = get_area(H.loc)
		if(H && ishuman(H) && H.stat != DEAD && H != current_victim && H.has_dna() && !H.dna.check_mutation(CLUWNEMUT) && !is_type_in_typecache(A, invalid_area_typecache) && is_station_level(H.z))
			current_victim = H
			interest = 0
			stage = STAGE_HAUNT
			return target = current_victim

	message_admins("Floor Cluwne was deleted due to a lack of valid targets, if this was a manually targeted instance please re-evaluate your choice.")
	qdel(src)

/**
 * Using an external variable to modify the basic behaviour of a proc like this is confusing and unnecessary.
 * Instead, there should be two procs, one for the manifest behavior animation and one for demanifesting. If not this, then the "manifested" variable should be set within this proc instead.
 * It is intuitive for this proc to implicitly toggle it.
 * - AP
**/
/mob/living/simple_animal/hostile/floor_cluwne/proc/Manifest()//handles disappearing and appearance anim
	if(manifested)
		mobility_flags &= ~MOBILITY_MOVE
		update_mobility()
		cluwnehole = new(src.loc)
		addtimer(CALLBACK(src, TYPE_PROC_REF(/mob/living/simple_animal/hostile/floor_cluwne, Appear)), MANIFEST_DELAY)
	else
		layer = GAME_PLANE
		invisibility = INVISIBILITY_OBSERVER
		density = FALSE
		mobility_flags |= MOBILITY_MOVE
		update_mobility()
		if(cluwnehole)
			qdel(cluwnehole)


/mob/living/simple_animal/hostile/floor_cluwne/proc/Appear()//handled in a seperate proc so floor cluwne doesn't appear before the animation finishes
	layer = LYING_MOB_LAYER
	invisibility = FALSE
	density = TRUE

/mob/living/simple_animal/hostile/floor_cluwne/proc/Reset_View(screens, colour, mob/living/carbon/human/H)
	if(screens)
		for(var/whole_screen in screens)
			animate(whole_screen, transform = matrix(), time = 0.5 SECONDS, easing = QUAD_EASING)
	if(colour && H)
		H.client.color = colour

/mob/living/simple_animal/hostile/floor_cluwne/proc/On_Stage()
	var/mob/living/carbon/human/H = current_victim
	if(!H)
		FindTarget()
		return
	switch(stage)
		if(STAGE_HAUNT)
			if(prob(5))
				H.adjust_eye_blur(1)

			if(prob(5))
				H.playsound_local(src,'yogstation/sound/voice/cluwnelaugh2_reversed.ogg', 1)

			if(prob(5))
				H.playsound_local(src,'yogstation/sound/misc/bikehorn_creepy.ogg', 5)

			if(prob(3))
				var/obj/item/I = locate() in orange(H, 8)
				if(I && !I.anchored)
					I.throw_at(H, 4, 3)
					to_chat(H, span_warning("What threw that?"))

		if(STAGE_SPOOK)
			if(prob(4))
				var/turf/T = get_turf(H)
				T.handle_slip(H, 20)
				to_chat(H, span_warning("The floor shifts underneath you!"))

			if(prob(5))
				H.playsound_local(src,'yogstation/sound/voice/cluwnelaugh2.ogg', 2)

			if(prob(5))
				H.playsound_local(src,'yogstation/sound/voice/cluwnelaugh2_reversed.ogg', 2)

			if(prob(5))
				H.playsound_local(src,'yogstation/sound/misc/bikehorn_creepy.ogg', 10)
				to_chat(H, "<i>knoh</i>")

			if(prob(5))
				var/obj/item/I = locate() in orange(H, 8)
				if(I && !I.anchored)
					I.throw_at(H, 4, 3)
					to_chat(H, span_warning("What threw that?"))
					
			if(prob(2))
				to_chat(H, "<i>yalp ot tnaw I</i>")
				Appear()
				manifested = FALSE
				addtimer(CALLBACK(src, TYPE_PROC_REF(/mob/living/simple_animal/hostile/floor_cluwne, Manifest)), 2)
				current_victim.set_drugginess(rand(1,10))

		if(STAGE_TORMENT)
			if(prob(5))
				var/turf/T = get_turf(H)
				T.handle_slip(H, 20)
				to_chat(H, span_warning("The floor shifts underneath you!"))

			if(prob(3))
				playsound(src,pick('sound/spookoween/scary_horn.ogg', 'sound/spookoween/scary_horn2.ogg', 'sound/spookoween/scary_horn3.ogg'), 30, 1)

			if(prob(3))
				playsound(src,'yogstation/sound/voice/cluwnelaugh1.ogg', 30, 1)

			if(prob(3))
				playsound(src,'yogstation/sound/voice/cluwnelaugh2_reversed.ogg', 30, 1)

			if(prob(5))
				playsound(src,'yogstation/sound/misc/bikehorn_creepy.ogg', 30, 1)

			if(prob(4))
				for(var/obj/item/I in orange(H, 8))
					if(I && !I.anchored)
						I.throw_at(H, 4, 3)
				to_chat(H, span_warning("What the hell?!"))

			if(prob(2))
				to_chat(H, span_warning("Something feels very wrong..."))
				H.playsound_local(src,'sound/hallucinations/behind_you1.ogg', 25)
				H.flash_act()

			if(prob(2))
				to_chat(H, "<i>!?REHTOMKNOH eht esiarp uoy oD</i>")
				to_chat(H, span_warning("Something grabs your foot!"))
				H.playsound_local(src,'sound/hallucinations/i_see_you1.ogg', 25)
				H.Stun(20)

			if(prob(3))
				to_chat(H, "<i>KNOH ?od nottub siht seod tahW</i>")
				for(var/turf/open/O in range(src, 6))
					O.MakeSlippery(TURF_WET_WATER, 10)
					playsound(src, 'sound/effects/meteorimpact.ogg', 30, 1)

			if(prob(1))
				to_chat(H, span_userdanger("WHAT THE FUCK IS THAT?!"))
				to_chat(H, "<i>.KNOH !nuf hcum os si uoy htiw gniyalP .KNOH KNOH KNOH</i>")
				H.playsound_local(src,'sound/hallucinations/im_here1.ogg', 25)
				H.reagents.add_reagent(/datum/reagent/toxin/mindbreaker, 3)
				H.reagents.add_reagent(/datum/reagent/consumable/laughter, 5)
				H.reagents.add_reagent(/datum/reagent/mercury, 3)
				Appear()
				manifested = FALSE
				addtimer(CALLBACK(src, TYPE_PROC_REF(/mob/living/simple_animal/hostile/floor_cluwne, Manifest)), 2)
				for(var/obj/machinery/light/L in range(H, 8))
					L.flicker()

		if(STAGE_ATTACK)
			if(!eating)
				Found_You()
				for(var/I in getline(src,H))
					var/turf/T = I
					if(T.density)
						forceMove(H.loc)
					for(var/obj/structure/O in T)
						if(O.density || istype(O, /obj/machinery/door/airlock))
							forceMove(H.loc)
				to_chat(H, span_userdanger("You feel the floor closing in on your feet!"))
				H.Paralyze(300)
				H.emote("scream")
				H.adjustBruteLoss(10)
				manifested = TRUE
				Manifest()
				if(!eating)
					empulse(src, EMP_HEAVY, 6)
					addtimer(CALLBACK(src, TYPE_PROC_REF(/mob/living/simple_animal/hostile/floor_cluwne, Grab), H), 50, TIMER_OVERRIDE|TIMER_UNIQUE)
					for(var/turf/open/O in range(src, 6))
						O.MakeSlippery(TURF_WET_LUBE, 30)
						playsound(src, 'sound/effects/meteorimpact.ogg', 30, 1)
				eating = TRUE


/mob/living/simple_animal/hostile/floor_cluwne/proc/Grab(mob/living/carbon/human/H)
	to_chat(H, span_userdanger("You feel a cold, gloved hand clamp down on your ankle!"))
	for(var/I in 1 to get_dist(src, H))
		if(do_after(src, 0.5 SECONDS, H))
			Found_You()
			step_towards(H, src)
			playsound(H, pick('yogstation/sound/effects/bodyscrape-01.ogg', 'yogstation/sound/effects/bodyscrape-02.ogg'), 20, 1, -4)
			if(prob(40))
				H.emote("scream")
			else if(prob(25))
				H.say(pick("HELP ME!!","IT'S GOT ME!!","DON'T LET IT TAKE ME!!",";SOMETHING'S KILLING ME!!","HOLY FUCK!!"))
				playsound(src, pick('yogstation/sound/voice/cluwnelaugh1.ogg', 'yogstation/sound/voice/cluwnelaugh2.ogg', 'yogstation/sound/voice/cluwnelaugh3.ogg'), 50, 1)

	if(get_dist(src,H) <= 1)
		visible_message(span_danger("[src] begins dragging [H] under the floor!"))
		if(do_after(src, 5 SECONDS, H) && eating)
			H.become_blind()
			H.layer = GAME_PLANE
			H.invisibility = INVISIBILITY_OBSERVER
			H.density = FALSE
			H.anchored = TRUE
			addtimer(CALLBACK(src, TYPE_PROC_REF(/mob/living/simple_animal/hostile/floor_cluwne, Kill), H), 100, TIMER_OVERRIDE|TIMER_UNIQUE)
			visible_message(span_danger("[src] pulls [H] under!"))
			to_chat(H, span_userdanger("[src] drags you underneath the floor!"))
		else
			eating = FALSE
	else
		eating = FALSE
	manifested = FALSE
	Manifest()


/mob/living/simple_animal/hostile/floor_cluwne/proc/Kill(mob/living/carbon/human/H)
	if(!istype(H) || !H.client)
		Acquire_Victim()
		return
	playsound(H, 'yogstation/sound/effects/cluwne_feast.ogg', 100, 0, -4)
	var/old_color = H.client.color
	var/red_splash = list(1,0,0,0.8,0.2,0, 0.8,0,0.2,0.1,0,0)
	var/pure_red = list(0,0,0,0,0,0,0,0,0,1,0,0)
	H.client.color = pure_red
	animate(H.client,color = red_splash, time = 1 SECONDS, easing = SINE_EASING|EASE_OUT)
	for(var/turf/T in orange(H, 4))
		H.add_splatter_floor(T)
	if(do_after(src, 5 SECONDS, H))
		H.unequip_everything()//more runtime prevention
		if(prob(75))
			H.gib(FALSE)
		else
			H.cluwneify()
			H.adjustBruteLoss(30)
			H.adjustOrganLoss(ORGAN_SLOT_BRAIN, 100)
			H.cure_blind()
			H.layer = initial(H.layer)
			H.invisibility = initial(H.invisibility)
			H.density = initial(H.density)
			H.anchored = initial(H.anchored)
			H.adjust_eye_blur(10)
			animate(H.client,color = old_color, time = 2 SECONDS)

	eating = FALSE
	switch_stage = switch_stage * 0.75 //he gets faster after each feast
	for(var/mob/M in GLOB.player_list)
		M.playsound_local(get_turf(M), 'yogstation/sound/misc/honk_echo_distant.ogg', 50, 1, pressure_affected = FALSE)

	interest = 0
	stage = STAGE_HAUNT
	Acquire_Victim()

//manifestation animation
/obj/effect/temp_visual/fcluwne_manifest
	icon = 'yogstation/icons/turf/floors.dmi'
	icon_state = "fcluwne_open"
	layer = TURF_LAYER
	duration = 600
	randomdir = FALSE

/obj/effect/temp_visual/fcluwne_manifest/Initialize(mapload)
	. = ..()
	playsound(src, 'yogstation/sound/misc/floor_cluwne_emerge.ogg', 100, 1)
	flick("fcluwne_manifest",src)

/obj/effect/dummy/floorcluwne_orbit
	name = "floor cluwne"
	desc = "If you have this, tell a coder or admin!"

/obj/effect/dummy/floorcluwne_orbit/Initialize(mapload)
	. = ..()
	GLOB.floor_cluwnes++
	name += " ([GLOB.floor_cluwnes])"
	GLOB.poi_list += src

/obj/effect/dummy/floorcluwne_orbit/Destroy()
	. = ..()
	GLOB.poi_list -= src

#undef STAGE_HAUNT
#undef STAGE_SPOOK
#undef STAGE_TORMENT
#undef STAGE_ATTACK
#undef MANIFEST_DELAY
