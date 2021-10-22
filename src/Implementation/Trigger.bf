using System;
using Pile;

namespace Dimtoo
{
	// - triggers system! -- each component will know from state if an overlap is new or old!

	struct TriggerBody
	{

	}

	class TriggerSystem : ComponentSystem, ITickSystem
	{
		static Type[?] wantsComponents = .(typeof(Transform), typeof(CollisionBody), typeof(TriggerBody));
		this
		{
			signatureTypes = wantsComponents;
		}

		public void Tick()
		{
			// We assume to be called after movement has taken place, otherwise updating triggers wouldn't make sense
			// i.e.: (various updates adding force, setting movement) -> collision tick & other movement finalizing things
			//		 -> trigger tick -> ... (movement & now also contact info fresh for next cycle)

			for (let e in entities)
			{

			}
		}
	}
}
