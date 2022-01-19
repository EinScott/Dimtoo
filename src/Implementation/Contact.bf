using System;
using System.Collections;
using Pile;

namespace Dimtoo
{
	// TODO: also track just "contacts" of the four edges -> on ground, on wall...
	// COUNTS ONLY CONTACTS WITH SOLID EDGES!! (or make this an option?)

	struct ContactBody
	{
		public SizedList<ContactInfo, const 8> data;
		public Edge mask; // Quick overview of which edges are in contact
	}

	struct ContactInfo
	{
		public Entity other;
		public Edge myContactEdge;
		public int myColliderIndex, otherColliderIndex;
	}

	class ContactSystem : ComponentSystem
	{
		static Type[?] wantsComponents = .(typeof(Transform), typeof(CollisionBody), typeof(ContactBody));
		this
		{
			signatureTypes = wantsComponents;
		}

		public void TickPostColl()
		{
			// We assume to be called after movement has taken place, otherwise looking which overlaps exist wouldn't make sense
			// i.e.: (various updates adding force, setting movement) -> collision tick & other movement finalizing things
			//		 -> contact tick -> ... (movement & now also contact info fresh for next cycle)
		}
	}
}
