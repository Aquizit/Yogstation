/datum/bounty/item/mech/New()
	..()
	description = "Upper management has requested one [name] mech be sent as soon as possible. Ship it to receive a large payment."

/datum/bounty/item/mech/ship(obj/O)
	if(!applies_to(O))
		return
	return ..()

/datum/bounty/item/mech/mark_high_priority(scale_reward)
	return ..(max(scale_reward * 0.7, 1.2))

/datum/bounty/item/mech/firefighter
	name = "APLU MK-II \"Firefighter\""
	reward = 18000
	wanted_types = list(/obj/mecha/working/ripley/firefighter)

/datum/bounty/item/mech/clarke
	name = "Clarke"
	reward = 16000
	wanted_types = list(/obj/mecha/working/clarke)

/datum/bounty/item/mech/odysseus
	name = "Odysseus"
	reward = 11000
	wanted_types = list(/obj/mecha/medical/odysseus)

/datum/bounty/item/mech/gygax
	name = "Gygax"
	reward = 28000
	wanted_types = list(/obj/mecha/combat/gygax)

/datum/bounty/item/mech/durand
	name = "Durand"
	reward = 20000
	wanted_types = list(/obj/mecha/combat/durand)
