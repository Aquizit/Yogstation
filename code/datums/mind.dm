/*	Note from Carnie:
		The way datum/mind stuff works has been changed a lot.
		Minds now represent IC characters rather than following a client around constantly.

	Guidelines for using minds properly:

	-	Never mind.transfer_to(ghost). The var/current and var/original of a mind must always be of type mob/living!
		ghost.mind is however used as a reference to the ghost's corpse

	-	When creating a new mob for an existing IC character (e.g. cloning a dead guy or borging a brain of a human)
		the existing mind of the old mob should be transfered to the new mob like so:

			mind.transfer_to(new_mob)

	-	You must not assign key= or ckey= after transfer_to() since the transfer_to transfers the client for you.
		By setting key or ckey explicitly after transferring the mind with transfer_to you will cause bugs like DCing
		the player.

	-	IMPORTANT NOTE 2, if you want a player to become a ghost, use mob.ghostize() It does all the hard work for you.

	-	When creating a new mob which will be a new IC character (e.g. putting a shade in a construct or randomly selecting
		a ghost to become a xeno during an event). Simply assign the key or ckey like you've always done.

			new_mob.key = key

		The Login proc will handle making a new mind for that mobtype (including setting up stuff like mind.name). Simple!
		However if you want that mind to have any special properties like being a traitor etc you will have to do that
		yourself.

*/

/datum/mind
	/// Key of the mob
	var/key
	/// The name linked to this mind
	var/name
	/// Current mob this mind datum is attached to
	var/mob/living/current
	/// Is this mind active?
	var/active = FALSE

	var/memory

	/// Job datum indicating the mind's role. This should always exist after initialization, as a reference to a singleton.
	var/assigned_role

	var/role_alt_title

	var/special_role
	var/list/restricted_roles = list()
	var/list/datum/objective/objectives = list()

	/// The owner of this mind's ability to perform certain kinds of tasks.
	var/list/skills = list(
		SKILL_PHYSIOLOGY = EXP_NONE,
		SKILL_MECHANICAL = EXP_NONE,
		SKILL_TECHNICAL = EXP_NONE,
		SKILL_SCIENCE = EXP_NONE,
		SKILL_FITNESS = EXP_NONE,
	)

	/// Progress towards increasing their skill level.
	var/list/exp_progress = list(
		SKILL_PHYSIOLOGY = 0,
		SKILL_MECHANICAL = 0,
		SKILL_TECHNICAL = 0,
		SKILL_SCIENCE = 0,
		SKILL_FITNESS = 0,
	)

	/// One-time experience gains that have already been acquired.
	var/list/exp_sources = list()

	/// Free skill points to allocate
	var/skill_points = 0

	var/linglink
	var/datum/martial_art/martial_art
	var/static/default_martial_art = new/datum/martial_art
	var/miming = FALSE // Mime's vow of silence
	var/list/antag_datums
	/// this mind's ANTAG_HUD should have this icon_state
	var/antag_hud_icon_state = null
	///this mind's antag HUD
	var/datum/atom_hud/alternate_appearance/basic/antagonist_hud/antag_hud = null //this mind's antag HUD
	var/damnation_type = 0
	var/datum/mind/soulOwner //who owns the soul.  Under normal circumstances, this will point to src
	var/hasSoul = TRUE // If false, renders the character unable to sell their soul.
	var/holy_role = NONE //is this person a chaplain or admin role allowed to use bibles, Any rank besides 'NONE' allows for this.

	///If this mind's master is another mob (i.e. adamantine golems). Weakref of a /living.
	var/datum/weakref/enslaved_to
	var/datum/language_holder/language_holder
	var/unconvertable = FALSE
	var/late_joiner = FALSE

	var/last_death = 0

	var/force_escaped = FALSE  // Set by Into The Sunset command of the shuttle manipulator

	var/list/learned_recipes //List of learned recipe TYPES.

	var/flavour_text = null
	///Are we zombified/uncloneable?
	var/zombified = FALSE
	///Weakref to thecharacter we joined in as- either at roundstart or latejoin, so we know for persistent scars if we ended as the same person or not
	var/datum/weakref/original_character
	/// The index for what character slot, if any, we were loaded from, so we can track persistent scars on a per-character basis. Each character slot gets PERSISTENT_SCAR_SLOTS scar slots
	var/original_character_slot_index
	/// What scar slot we have loaded, so we don't have to constantly check the savefile
	var/current_scar_slot
	/// The index for our current scar slot, so we don't have to constantly check the savefile (unlike the slots themselves, this index is independent of selected char slot, and increments whenever a valid char is joined with)
	var/current_scar_slot_index

	/// If they have used the afk verb recently
	var/afk_verb_used = FALSE
	/// The timer for the afk verb
	var/afk_verb_timer

/datum/mind/New(_key)
	key = _key
	soulOwner = src
	martial_art = default_martial_art
	RegisterSignal(src, SIGNAL_ADDTRAIT(TRAIT_EXCEPTIONAL_SKILL), PROC_REF(update_skills))

/datum/mind/Destroy()
	SSticker.minds -= src
	QDEL_NULL(antag_hud)
	QDEL_LIST(antag_datums)
	QDEL_NULL(language_holder)
	current = null
	soulOwner = null
	return ..()

/datum/mind/proc/get_language_holder()
	if(!language_holder)
		language_holder = new (src)

	return language_holder

/datum/mind/proc/set_current(mob/new_current)
	if(new_current && QDELETED(new_current))
		CRASH("Tried to set a mind's current var to a qdeleted mob, what the fuck")
	if(current)
		UnregisterSignal(src, COMSIG_QDELETING)
	current = new_current
	if(current)
		RegisterSignal(src, COMSIG_QDELETING, PROC_REF(clear_current))

/datum/mind/proc/clear_current(datum/source)
	SIGNAL_HANDLER
	set_current(null)

/datum/mind/proc/transfer_to(mob/new_character, force_key_move = 0)
	set_original_character(null)
	var/mood_was_enabled = FALSE//Yogs -- Mood Preferences
	if(current)	// remove ourself from our old body's mind variable
		// Yogs start -- Mood preferences
		if(current.client && current.client.prefs.read_preference(/datum/preference/toggle/mood_enabled))
			mood_was_enabled = TRUE
		else if(ishuman(current) && CONFIG_GET(flag/disable_human_mood))
			var/mob/living/carbon/human/H = current
			if(H.mood_enabled)
				mood_was_enabled = TRUE
				var/datum/component/mood/c = H.GetComponent(/datum/component/mood)
				if(c)
					qdel(c)
		// Yogs End
		current.mind = null
		UnregisterSignal(current, COMSIG_GLOB_MOB_DEATH)
		UnregisterSignal(current, COMSIG_MOB_SAY)
		SStgui.on_transfer(current, new_character)

	if(key)
		if(new_character.key != key) //if we're transferring into a body with a key associated which is not ours
			new_character.ghostize(TRUE) //we'll need to ghostize so that key isn't mobless.
	else
		key = new_character.key

	if(new_character.mind) //disassociate any mind currently in our new body's mind variable
		new_character.mind.set_current(null)

	var/mob/living/old_current = current
	if(current)
		current.transfer_observers_to(new_character)	//transfer anyone observing the old character to the new one
	set_current(new_character) //associate ourself with our new body
	QDEL_NULL(antag_hud)
	new_character.mind = src							//and associate our new body with ourself
	antag_hud = new_character.add_alt_appearance(/datum/atom_hud/alternate_appearance/basic/antagonist_hud, "combo_hud", src)
	for(var/a in antag_datums)	//Makes sure all antag datums effects are applied in the new body
		var/datum/antagonist/A = a
		A.on_body_transfer(old_current, current)
	if(iscarbon(new_character))
		var/mob/living/carbon/C = new_character
		C.last_mind = src
		// Yogs start -- Mood preferences
		if(ishuman(new_character) && mood_was_enabled && !new_character.GetComponent(/datum/component/mood))
			var/mob/living/carbon/human/H = C
			H.AddComponent(/datum/component/mood)
		// Yogs End
	transfer_martial_arts(new_character)
	transfer_parasites()
	RegisterSignal(new_character, COMSIG_GLOB_MOB_DEATH, PROC_REF(set_death_time))
	if(accent_name)
		RegisterSignal(new_character, COMSIG_MOB_SAY, PROC_REF(handle_speech))
	if(active || force_key_move)
		new_character.key = key		//now transfer the key to link the client to our new body
	if(new_character.client)
		new_character.client.init_verbs() // re-initialize character specific verbs
		LAZYCLEARLIST(new_character.client.recent_examines)
	current.update_atom_languages()
	SEND_SIGNAL(src, COMSIG_MIND_TRANSFERRED, old_current)
	SEND_SIGNAL(current, COMSIG_MOB_MIND_TRANSFERRED_INTO)

//I cannot trust you fucks to do this properly
/datum/mind/proc/set_original_character(new_original_character)
	original_character = WEAKREF(new_original_character)

/datum/mind/proc/set_death_time()
	last_death = world.time

/datum/mind/proc/store_memory(new_text)
	var/newlength = length_char(memory) + length_char(new_text)
	if (newlength > MAX_MESSAGE_LEN * 100)
		memory = copytext_char(memory, -newlength-MAX_MESSAGE_LEN * 100)
	memory += "[new_text]<BR>"

/datum/mind/proc/wipe_memory()
	memory = null

// Datum antag mind procs
/datum/mind/proc/add_antag_datum(datum_type_or_instance, team)
	if(!datum_type_or_instance)
		return
	if(has_antag_datum(datum_type_or_instance)) //if they already have it, don't give it again
		return
	var/datum/antagonist/A
	if(!ispath(datum_type_or_instance))
		A = datum_type_or_instance
		if(!istype(A))
			return
	else
		A = new datum_type_or_instance()
	//Choose snowflake variation if antagonist handles it
	var/datum/antagonist/S = A.specialization(src)
	if(S && S != A)
		qdel(A)
		A = S
	if(!A.can_be_owned(src))
		qdel(A)
		return
	A.owner = src
	LAZYADD(antag_datums, A)
	A.create_team(team)
	var/datum/team/antag_team = A.get_team()
	if(antag_team)
		antag_team.add_member(src)
		if(!antag_team.antag_path)
			antag_team.antag_path = S.type
	A.on_gain()
	log_game("[key_name(src)] has gained antag datum [A.name]([A.type])")
	return A

/datum/mind/proc/remove_antag_datum(datum_type)
	if(!datum_type)
		return
	var/datum/antagonist/A = has_antag_datum(datum_type)
	if(A)
		A.on_removal()
		return TRUE


/datum/mind/proc/remove_all_antag_datums() //For the Lazy amongst us.
	for(var/a in antag_datums)
		var/datum/antagonist/A = a
		A.on_removal()

/datum/mind/proc/has_antag_datum(datum_type, check_subtypes = TRUE)
	if(!datum_type)
		return
	. = FALSE
	for(var/a in antag_datums)
		var/datum/antagonist/A = a
		if(check_subtypes && istype(A, datum_type))
			return A
		else if(A.type == datum_type)
			return A

/datum/mind/proc/equip_traitor(employer = "The Syndicate", silent = FALSE, datum/antagonist/uplink_owner)
	if(!current)
		return
	var/mob/living/carbon/human/traitor_mob = current
	if (!istype(traitor_mob))
		return

	traitor_mob.add_skill_points(EXP_LOW) // one extra skill point
	ADD_TRAIT(src, TRAIT_EXCEPTIONAL_SKILL, type)

	var/list/all_contents = traitor_mob.get_all_contents()
	var/obj/item/modular_computer/PDA = locate() in all_contents
	var/obj/item/radio/R = locate() in all_contents
	var/obj/item/pen/P

	if (PDA) // Prioritize PDA pen, otherwise the pocket protector pens will be chosen, which causes numerous ahelps about missing uplink
		P = locate() in PDA
	if (!P) // If we couldn't find a pen in the PDA, or we didn't even have a PDA, do it the old way
		P = locate() in all_contents
		if(!P) // I do not have a pen.
			var/obj/item/pen/inowhaveapen
			if(istype(traitor_mob.back,/obj/item/storage)) //ok buddy you better have a backpack!
				inowhaveapen = new /obj/item/pen(traitor_mob.back)
			else
				inowhaveapen = new /obj/item/pen(traitor_mob.loc)
				traitor_mob.put_in_hands(inowhaveapen) // I hope you don't have arms and your traitor pen gets stolen for all this trouble you've caused.
			P = inowhaveapen

	var/obj/item/uplink_loc
	var/implant = FALSE

	var/uplink_spawn_location = traitor_mob.client?.prefs?.read_preference(/datum/preference/choiced/uplink_location)
	switch (uplink_spawn_location)
		if(UPLINK_PDA)
			uplink_loc = PDA
			if(!uplink_loc)
				uplink_loc = R
			if(!uplink_loc)
				uplink_loc = P
		if(UPLINK_RADIO)
			uplink_loc = R
			if(!uplink_loc)
				uplink_loc = PDA
			if(!uplink_loc)
				uplink_loc = P
		if(UPLINK_PEN)
			uplink_loc = P
			if(!uplink_loc)
				uplink_loc = PDA
			if(!uplink_loc)
				uplink_loc = R
		if(UPLINK_IMPLANT)
			implant = TRUE

	if(!uplink_loc) // We've looked everywhere, let's just implant you
		implant = TRUE

	if(!implant)
		. = uplink_loc
		var/datum/component/uplink/U = uplink_loc.AddComponent(/datum/component/uplink, traitor_mob.key)
		if(!U)
			CRASH("Uplink creation failed.")
		U.setup_unlock_code()
		if(!silent)
			if(uplink_loc == R)
				to_chat(traitor_mob, "[employer] has cunningly disguised a Syndicate Uplink as your [R.name]. Simply dial the frequency [format_frequency(U.unlock_code)] to unlock its hidden features.")
			else if(uplink_loc == PDA)
				to_chat(traitor_mob, "[employer] has cunningly disguised a Syndicate Uplink as your [PDA.name]. Simply enter the code \"[U.unlock_code]\" into the ringtone select to unlock its hidden features.")
			else if(uplink_loc == P)
				to_chat(traitor_mob, "[employer] has cunningly disguised a Syndicate Uplink as your [P.name]. Simply twist the top of the pen [english_list(U.unlock_code)] from its starting position to unlock its hidden features.")
		if(uplink_owner)
			uplink_owner.antag_memory += U.unlock_note + "<br>"
		else
			traitor_mob.mind.store_memory(U.unlock_note)
	else
		var/obj/item/implant/uplink/starting/I = new(traitor_mob)
		I.implant(traitor_mob, null, silent = TRUE)
		if(!silent)
			to_chat(traitor_mob, "<span class='boldnotice'>[employer] has cunningly implanted you with a Syndicate Uplink (although uplink implants cost valuable TC, so you will have slightly less). Simply trigger the uplink to access it.</span>")
		return I


//Register a signal to the creator such that if they gain an antagonist datum, they also get it
/datum/mind/proc/add_creator_antag(datum/mind/creator, datum/antagonist/antag)
	var/antag_type = antag.type

	//don't give them a full antag status if there's a suitable servant antag datum
	var/list/antag_downgrade = list(
		/datum/antagonist/darkspawn = /datum/antagonist/psyche,
		/datum/antagonist/thrall = /datum/antagonist/psyche
	)
	if(antag_type in antag_downgrade)
		antag_type = antag_downgrade[antag_type]

	add_antag_datum(antag_type)

/datum/mind/proc/remove_creator_antag(datum/mind/creator, datum/antagonist/antag)
	var/antag_type = antag.type

	//make sure to do it here too so the proper tag is removed
	var/list/antag_downgrade = list(
		/datum/antagonist/darkspawn = /datum/antagonist/psyche,
		/datum/antagonist/thrall = /datum/antagonist/psyche
	)
	if(antag_type in antag_downgrade)
		antag_type = antag_downgrade[antag_type]

	remove_antag_datum(antag_type)

//Link a new mobs mind to the creator of said mob. They will join any team they are currently on, and will only switch teams when their creator does.
/datum/mind/proc/enslave_mind_to_creator(mob/living/creator)
	RegisterSignal(creator.mind, COMSIG_ANTAGONIST_GAINED, PROC_REF(add_creator_antag)) //re-enslave to the new antag
	RegisterSignal(creator.mind, COMSIG_ANTAGONIST_REMOVED, PROC_REF(remove_creator_antag)) //remove enslavement to the antag

	if(iscultist(creator))
		current.add_cultist()

	else if(IS_REVOLUTIONARY(creator))
		var/datum/antagonist/rev/converter = creator.mind.has_antag_datum(/datum/antagonist/rev,TRUE)
		converter.add_revolutionary(src,FALSE)

	else if(is_servant_of_ratvar(creator))
		add_servant_of_ratvar(current)

	else if(IS_NUKE_OP(creator))
		var/datum/antagonist/nukeop/converter = creator.mind.has_antag_datum(/datum/antagonist/nukeop,TRUE)
		var/datum/antagonist/nukeop/N = new()
		N.send_to_spawnpoint = FALSE
		N.nukeop_outfit = null
		add_antag_datum(N,converter.nuke_team)

	else if(is_team_darkspawn(creator))
		add_antag_datum(/datum/antagonist/psyche)


	enslaved_to = WEAKREF(creator)

	current.faction |= creator.faction
	creator.faction |= current.faction

	if(creator.mind.special_role)
		message_admins("[ADMIN_LOOKUPFLW(current)] has been created by [ADMIN_LOOKUPFLW(creator)], an antagonist.")
		to_chat(current, span_userdanger("Despite your creators current allegiances, your true master remains [creator.real_name]. If their loyalties change, so do yours. This will never change unless your creator's body is destroyed."))

/datum/mind/proc/show_memory(mob/recipient, window=1)
	if(!recipient)
		recipient = current
	var/output = ""
	output += "<B>[current.real_name]'s Memories:</B><br>"
	output += memory


	var/list/all_objectives = list()
	for(var/datum/antagonist/A in antag_datums)
		output += A.task_memory
		output += A.antag_memory
		all_objectives |= A.objectives

	if(all_objectives.len)
		output += "<B>Objectives:</B>"
		var/obj_count = 1
		for(var/datum/objective/objective in all_objectives)
			output += "<br><B>Objective #[obj_count++]</B>: [objective.explanation_text]"
			if (objective.optional)
				output += " - This objective is optional and not tracked, so just have fun with it!"
			var/list/datum/mind/other_owners = objective.get_owners() - src
			if(other_owners.len)
				output += "<ul>"
				for(var/datum/mind/M in other_owners)
					output += "<li>Conspirator: [M.name]</li>"
				output += "</ul>"

	if(window)
		output = "<HTML><HEAD><meta charset='UTF-8'></HEAD><BODY>" + output + "</BODY></HTML>"
		recipient << browse(output,"window=memory")
	else if(all_objectives.len || memory)
		to_chat(recipient, "<i>[output]</i>")

/datum/mind/Topic(href, href_list)
	if(!check_rights(R_ADMIN))
		return

	var/self_antagging = usr == current

	if(href_list["add_antag"])
		add_antag_wrapper(text2path(href_list["add_antag"]),usr)
	if(href_list["remove_antag"])
		var/datum/antagonist/A = locate(href_list["remove_antag"]) in antag_datums
		if(!istype(A))
			to_chat(usr,span_warning("Invalid antagonist ref to be removed."))
			return
		A.admin_remove(usr)

	if (href_list["role_edit"])
		var/new_role = input("Select new role", "Assigned role", assigned_role) as null|anything in sortList(get_all_jobs())
		if (!new_role)
			return
		assigned_role = new_role

	else if (href_list["memory_edit"])
		var/new_memo = stripped_multiline_input(usr, "Write new memory", "Memory", memory, MAX_MESSAGE_LEN)
		if (isnull(new_memo))
			return
		memory = new_memo

	else if (href_list["obj_edit"] || href_list["obj_add"])
		var/objective_pos //Edited objectives need to keep same order in antag objective list
		var/def_value
		var/datum/antagonist/target_antag
		var/datum/objective/old_objective //The old objective we're replacing/editing
		var/datum/objective/new_objective //New objective we're be adding

		if(href_list["obj_edit"])
			for(var/datum/antagonist/A in antag_datums)
				old_objective = locate(href_list["obj_edit"]) in A.objectives
				if(old_objective)
					target_antag = A
					objective_pos = A.objectives.Find(old_objective)
					break
			if(!old_objective)
				to_chat(usr,"Invalid objective.")
				return
		else
			if(href_list["target_antag"])
				var/datum/antagonist/X = locate(href_list["target_antag"]) in antag_datums
				if(X)
					target_antag = X
			if(!target_antag)
				switch(antag_datums.len)
					if(0)
						target_antag = add_antag_datum(/datum/antagonist/custom)
					if(1)
						target_antag = antag_datums[1]
					else
						var/datum/antagonist/target = input("Which antagonist gets the objective:", "Antagonist", "(new custom antag)") as null|anything in sortList(antag_datums) + "(new custom antag)"
						if (QDELETED(target))
							return
						else if(target == "(new custom antag)")
							target_antag = add_antag_datum(/datum/antagonist/custom)
						else
							target_antag = target

		if(!GLOB.admin_objective_list)
			generate_admin_objective_list()

		if(old_objective)
			if(old_objective.name in GLOB.admin_objective_list)
				def_value = old_objective.name

		var/selected_type = input("Select objective type:", "Objective type", def_value) as null|anything in GLOB.admin_objective_list
		selected_type = GLOB.admin_objective_list[selected_type]
		if (!selected_type)
			return

		if(!old_objective)
			//Add new one
			new_objective = new selected_type
			new_objective.owner = src
			new_objective.admin_edit(usr)
			target_antag.objectives += new_objective
			message_admins("[key_name_admin(usr)] added a new objective for [current]: [new_objective.explanation_text]")
			log_admin("[key_name(usr)] added a new objective for [current]: [new_objective.explanation_text]")
		else
			if(old_objective.type == selected_type)
				//Edit the old
				old_objective.admin_edit(usr)
				new_objective = old_objective
			else
				//Replace the old
				new_objective = new selected_type
				new_objective.owner = src
				new_objective.admin_edit(usr)
				target_antag.objectives -= old_objective
				target_antag.objectives.Insert(objective_pos, new_objective)
			message_admins("[key_name_admin(usr)] edited [current]'s objective to [new_objective.explanation_text]")
			log_admin("[key_name(usr)] edited [current]'s objective to [new_objective.explanation_text]")

	else if (href_list["obj_delete"])
		var/datum/objective/objective
		for(var/datum/antagonist/A in antag_datums)
			objective = locate(href_list["obj_delete"]) in A.objectives
			if(istype(objective))
				A.objectives -= objective
				break
		if(!objective)
			to_chat(usr,"Invalid objective.")
			return
		//qdel(objective) Needs cleaning objective destroys
		message_admins("[key_name_admin(usr)] removed an objective for [current]: [objective.explanation_text]")
		log_admin("[key_name(usr)] removed an objective for [current]: [objective.explanation_text]")

	else if(href_list["obj_completed"])
		var/datum/objective/objective
		for(var/datum/antagonist/A in antag_datums)
			objective = locate(href_list["obj_completed"]) in A.objectives
			if(istype(objective))
				break
		if(!objective)
			to_chat(usr,"Invalid objective.")
			return
		objective.completed = !objective.completed
		log_admin("[key_name(usr)] toggled the win state for [current]'s objective: [objective.explanation_text]")

	else if (href_list["silicon"])
		switch(href_list["silicon"])
			if("unemag")
				var/mob/living/silicon/robot/R = current
				if (istype(R))
					R.SetEmagged(0)
					message_admins("[key_name_admin(usr)] has unemag'ed [R].")
					log_admin("[key_name(usr)] has unemag'ed [R].")

			if("unemagcyborgs")
				if(isAI(current))
					var/mob/living/silicon/ai/ai = current
					for (var/mob/living/silicon/robot/R in ai.connected_robots)
						R.SetEmagged(0)
					message_admins("[key_name_admin(usr)] has unemag'ed [ai]'s Cyborgs.")
					log_admin("[key_name(usr)] has unemag'ed [ai]'s Cyborgs.")

	else if (href_list["common"])
		switch(href_list["common"])
			if("undress")
				for(var/obj/item/W in current)
					current.dropItemToGround(W, TRUE) //The TRUE forces all items to drop, since this is an admin undress.
			if("takeuplink")
				take_uplink()
				memory = null//Remove any memory they may have had.
				log_admin("[key_name(usr)] removed [current]'s uplink.")
			if("crystals")
				if(check_rights(R_ADMIN, 0)) //YOGS - changes R_FUN to R_ADMIN
					var/datum/component/uplink/U = find_syndicate_uplink()
					if(U)
						var/crystals = input("Amount of telecrystals for [key]","Syndicate uplink", U.telecrystals) as null | num
						if(!isnull(crystals))
							U.telecrystals = crystals
							message_admins("[key_name_admin(usr)] changed [current]'s telecrystal count to [crystals].")
							log_admin("[key_name(usr)] changed [current]'s telecrystal count to [crystals].")
			if("uplink")
				if(!equip_traitor())
					to_chat(usr, span_danger("Equipping a syndicate failed!"))
					log_admin("[key_name(usr)] tried and failed to give [current] an uplink.")
				else
					log_admin("[key_name(usr)] gave [current] an uplink.")

	else if (href_list["obj_announce"])
		announce_objectives()

	// yogs start - Donor features, quiet round
	else if (href_list["quiet_override"])
		quiet_round = FALSE
		message_admins("[key_name_admin(usr)] has disabled [current]'s quiet round mode.")
		log_admin("[key_name(usr)] has disabled [current]'s quiet round mode.")
	// yogs end

	//Something in here might have changed your mob
	if(self_antagging && (!usr || !usr.client) && current.client)
		usr = current
	traitor_panel()


/datum/mind/proc/get_all_objectives()
	var/list/all_objectives = list()
	for(var/datum/antagonist/A in antag_datums)
		all_objectives |= A.objectives
		if(A.get_team())
			var/datum/team/antag_team = A.get_team()
			all_objectives |= antag_team.objectives
	return all_objectives

/datum/mind/proc/announce_objectives()
	var/obj_count = 1
	to_chat(current, span_notice("Your current objectives:"))
	for(var/objective in get_all_objectives())
		var/datum/objective/O = objective
		to_chat(current, "<B>[O.objective_name] #[obj_count]</B>: [O.explanation_text]")
		obj_count++

/datum/mind/proc/find_syndicate_uplink()
	var/list/L = current.get_all_contents()
	for (var/i in L)
		var/atom/movable/I = i
		. = I.GetComponent(/datum/component/uplink)
		if(.)
			break

/datum/mind/proc/take_uplink()
	qdel(find_syndicate_uplink())

/datum/mind/proc/make_Traitor()
	// yogs start - Donor features, quiet round
	if(quiet_round)
		return
	// yogs end
	if(!(has_antag_datum(/datum/antagonist/traitor)))
		add_antag_datum(/datum/antagonist/traitor)

/datum/mind/proc/make_Contractor_Support()
	if(!(has_antag_datum(/datum/antagonist/traitor/contractor_support)))
		add_antag_datum(/datum/antagonist/traitor/contractor_support)

/datum/mind/proc/make_Changeling()
	// yogs start - Donor features, quiet round
	if(quiet_round)
		return
	// yogs end
	var/datum/antagonist/changeling/C = has_antag_datum(/datum/antagonist/changeling)
	if(!C)
		C = add_antag_datum(/datum/antagonist/changeling)
		special_role = ROLE_CHANGELING
	return C

/datum/mind/proc/make_Heretic()
	if(quiet_round)
		return
	if(!(has_antag_datum(/datum/antagonist/heretic)))
		add_antag_datum(/datum/antagonist/heretic)

/datum/mind/proc/make_Wizard()
	// yogs start - Donor features, quiet round
	if(quiet_round)
		return
	// yogs end
	if(!has_antag_datum(/datum/antagonist/wizard))
		special_role = ROLE_WIZARD
		assigned_role = ROLE_WIZARD
		add_antag_datum(/datum/antagonist/wizard)


/datum/mind/proc/make_Cultist()
	// yogs start - Donor features, quiet round
	if(quiet_round)
		return
	// yogs end
	if(!current)
		return
	if(!has_antag_datum(/datum/antagonist/cult,TRUE))
		current.add_cultist(FALSE, equip=TRUE)
		special_role = ROLE_CULTIST
		to_chat(current, "<font color=\"purple\"><b><i>You catch a glimpse of the Realm of Nar'sie, The Geometer of Blood. You now see how flimsy your world is, you see that it should be open to the knowledge of Nar'sie.</b></i></font>")
		to_chat(current, "<font color=\"purple\"><b><i>Assist your new brethren in their dark dealings. Their goal is yours, and yours is theirs. You serve the Dark One above all else. Bring It back.</b></i></font>")

/datum/mind/proc/make_Rev()
	// yogs start - Donor features, quiet round
	if(quiet_round)
		return
	// yogs end
	var/datum/antagonist/rev/head/head = new()
	head.give_flash = TRUE
	head.give_hud = TRUE
	add_antag_datum(head)
	special_role = ROLE_REV_HEAD

/datum/mind/proc/owns_soul()
	return soulOwner == src

/datum/mind/proc/transfer_martial_arts(mob/living/new_character)
	if(!ishuman(new_character))
		return
	if(martial_art)
		if(martial_art.base) //Is the martial art temporary?
			martial_art.remove(new_character)
		else
			martial_art.teach(new_character)

/datum/mind/proc/get_ghost(even_if_they_cant_reenter, ghosts_with_clients)
	for(var/mob/dead/observer/G in (ghosts_with_clients ? GLOB.player_list : GLOB.dead_mob_list))
		if(G.mind == src)
			if(G.can_reenter_corpse || even_if_they_cant_reenter)
				return G
			break

/datum/mind/proc/grab_ghost(force)
	var/mob/dead/observer/G = get_ghost(even_if_they_cant_reenter = force)
	. = G
	if(G)
		G.reenter_corpse()


/datum/mind/proc/has_objective(objective_type)
	for(var/datum/antagonist/A in antag_datums)
		for(var/O in A.objectives)
			if(istype(O,objective_type))
				return TRUE

/datum/mind/proc/add_employee(company)
	for(var/datum/corporation/c in GLOB.corporations)
		if(istype(c, company))
			c.employees += src

/datum/mind/proc/remove_employee(company)
	for(var/datum/corporation/c in GLOB.corporations)
		if(istype(c, company))
			c.employees -= src

/datum/mind/proc/is_employee(company)
	for(var/datum/corporation/c in GLOB.corporations)
		if(istype(c, company))
			return src in c.employees

/mob/proc/sync_mind()
	mind_initialize()	//updates the mind (or creates and initializes one if one doesn't exist)
	mind.active = TRUE		//indicates that the mind is currently synced with a client

/// Returns the mob's skill level
/mob/proc/get_skill(skill)
	if(!mind)
		return EXP_NONE
	return mind.skills[skill]

/// Adjusts the mob's skill level
/mob/proc/adjust_skill(skill, amount=0, min_skill = EXP_NONE, max_skill = EXP_MASTER)
	if(!mind)
		return
	mind.skills[skill] = clamp(mind.skills[skill] + amount, min_skill, max_skill)

/// Checks if the mob's skill level meets a given threshold.
/mob/proc/skill_check(skill, amount)
	if(!mind)
		return FALSE
	return (mind.skills[skill] >= amount)

/// Adds progress towards increasing skill level. Returns TRUE if it added progress. Adding a source prevents gaining exp from that source again.
/mob/proc/add_exp(skill, amount, source)
	if(!mind)
		return FALSE
	if(!amount)
		return FALSE
	if(source && (source in mind.exp_sources))
		return FALSE
	mind.exp_sources.Add(source)
	mind.exp_progress[skill] += amount
	var/levels_gained = check_exp(skill)
	if(levels_gained) // remove an equal amount of unallocated skill points to prevent exploits
		mind.skill_points = max(mind.skill_points - levels_gained, 0)
	return TRUE

/// Levels up a skill if it has enough experience to do so.
/mob/proc/check_exp(skill)
	if(!mind)
		return FALSE
	var/current_level = get_skill(skill)
	var/exp_required = EXPERIENCE_PER_LEVEL * (2**current_level) // exp required scales exponentially
	if(mind.exp_progress[skill] < exp_required)
		return FALSE
	var/skill_cap = EXP_MASTER + HAS_MIND_TRAIT(src, TRAIT_EXCEPTIONAL_SKILL)
	var/levels_gained = min(round(log(2, 1 + (mind.exp_progress[skill] / exp_required))), max(skill_cap - current_level)) // in case you gained so much you go up more than one level
	if(levels_gained < 1)
		return FALSE
	var/levels_allocated = hud_used?.skill_menu ? hud_used.skill_menu.allocated_skills[skill] : 0
	if(levels_allocated > 0) // adjust any already allocated skills to prevent shenanigans (you know who you are)
		hud_used.skill_menu.allocated_points -= min(levels_gained, levels_allocated)
		hud_used.skill_menu.allocated_skills[skill] -= min(levels_gained, levels_allocated)
	mind.exp_progress[skill] -= exp_required * (((2**round(levels_gained + 1)) / 2) - 1)
	adjust_skill(skill, levels_gained, max_skill = skill_cap)
	to_chat(src, span_boldnotice("Your [skill] skill is now level [get_skill(skill)]!"))
	return levels_gained

/// Returns whether experience has been gained from a given source.
/mob/proc/has_exp(source)
	if(!mind)
		return FALSE
	return (source in mind.exp_sources) ? TRUE : FALSE

/// Adds skill points to be allocated at will.
/mob/proc/add_skill_points(amount)
	if(!mind)
		return
	mind.skill_points += amount
	throw_alert("skill points", /atom/movable/screen/alert/skill_up)

/// Called when [TRAIT_EXCEPTIONAL_SKILL] is added to the mob.
/datum/mind/proc/update_skills(datum/source)
	SIGNAL_HANDLER
	if(!current)
		return
	for(var/skill in skills)
		current.check_exp(skill)

/datum/mind/proc/has_martialart(string)
	if(martial_art && martial_art.id == string)
		return martial_art
	return FALSE

/mob/dead/new_player/sync_mind()
	return

/mob/dead/observer/sync_mind()
	return

//Initialisation procs
/mob/proc/mind_initialize()
	if(mind)
		mind.key = key

	else
		mind = new /datum/mind(key)
		SSticker.minds += mind
	if(!mind.name)
		mind.name = real_name
	mind.current = src
	// There's nowhere else to set this up, mind code makes me depressed
	mind.antag_hud = add_alt_appearance(/datum/atom_hud/alternate_appearance/basic/antagonist_hud, "combo_hud", mind)
	SEND_SIGNAL(src, COMSIG_MOB_MIND_INITIALIZED, mind)

/mob/living/carbon/mind_initialize()
	..()
	last_mind = mind

//HUMAN
/mob/living/carbon/human/mind_initialize()
	..()
	if(!mind.assigned_role)
		mind.assigned_role = "Unassigned" //default

//AI
/mob/living/silicon/ai/mind_initialize()
	..()
	mind.assigned_role = "AI"

//BORG
/mob/living/silicon/robot/mind_initialize()
	..()
	mind.assigned_role = "Cyborg"

//PAI
/mob/living/silicon/pai/mind_initialize()
	..()
	mind.assigned_role = ROLE_PAI
	mind.special_role = ""
